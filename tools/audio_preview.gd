extends SceneTree
## Renders EngineSynth offline to WAV files, so the sound can be checked
## without driving: a scripted run for every vehicle (idle, a blip, full
## throttle through the gears, a lift, a cruise), every surface, impacts and
## rain. Prints how long the synth takes per second of audio.
##   godot --headless --path . --script res://tools/audio_preview.gd -- <out dir>

const STEP := 1.0 / 60.0

var _cost_us := 0
var _audio_s := 0.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	for spec in Cars.LIST:
		var vmax := 80.0 if spec.get("type", "") == "f1" else (30.0 if spec.get("type", "") == "tank" else 52.0)
		_save(out_dir.path_join("%s_drive.wav" % spec["id"]), _drive(spec, vmax))
	_save(out_dir.path_join("surfaces.wav"), _surfaces(1.0))
	_save(out_dir.path_join("surfaces_tyres_only.wav"), _surfaces(0.0))
	_save(out_dir.path_join("impacts.wav"), _impacts())
	_save(out_dir.path_join("rain.wav"), _rain())
	_save(out_dir.path_join("tank_pivot.wav"), _pivot())
	print("synth cost: %.1f ms per second of audio" % (_cost_us / 1000.0 / _audio_s))
	quit()


func _synth(id: String) -> EngineSynth:
	var sy := EngineSynth.new()
	sy.setup(Cars.get_car(id))
	return sy


func _block(sy: EngineSynth, buf: PackedVector2Array) -> void:
	var n := int(EngineSynth.RATE * STEP)
	var t0 := Time.get_ticks_usec()
	buf.append_array(sy.render(n))
	_cost_us += Time.get_ticks_usec() - t0
	_audio_s += n / EngineSynth.RATE


## Simple longitudinal car with the game's gearbox and rpm logic.
func _drive(spec: Dictionary, vmax: float) -> PackedVector2Array:
	var sy := EngineSynth.new()
	sy.setup(spec)
	var gearing: float = spec["stats"].get("gearing", 1.0)
	var buf := PackedVector2Array()
	var v := 0.0
	var gear := 1
	var rpm := RallyCar.IDLE_RPM
	var shift_t := 0.0
	var t := 0.0
	while t < 14.0:
		var thr := 0.0
		if t > 1.5 and t < 2.3:
			thr = 1.0
		elif t > 3.0 and t < 10.0:
			thr = 1.0
		elif t > 12.5:
			thr = 0.4
		var road: float = v / RallyCar.WHEEL_RADIUS * RallyCar.GEAR_RATIOS[gear - 1] * RallyCar.FINAL_DRIVE * gearing * 60.0 / TAU
		var moving := t > 3.0
		var spinning := t > 3.0 and t < 3.8
		if moving:
			var acc := (9.0 * thr * (1.0 - v / vmax) if shift_t <= 0.0 else 0.0) - 1.5 - (2.0 if thr < 0.05 else 0.0)
			v = clampf(v + acc * STEP, 0.0, vmax)
		shift_t = maxf(shift_t - STEP, 0.0)
		if shift_t <= 0.0:
			if road > 7200.0 and gear < 5 and thr > 0.1:
				gear += 1
				shift_t = 0.2
				sy.shift(true)
			elif gear > 1 and ((road < 3300.0 and road * RallyCar.GEAR_RATIOS[gear - 2] / RallyCar.GEAR_RATIOS[gear - 1] < 6600.0) or road < 1800.0):
				gear -= 1
				shift_t = 0.15
				sy.shift(false)
		var target: float = road
		if spinning:
			target = maxf(target, lerpf(RallyCar.IDLE_RPM, RallyCar.REDLINE * 0.95, thr))
		target = clampf(maxf(target, RallyCar.IDLE_RPM + thr * 1500.0), RallyCar.IDLE_RPM, RallyCar.REDLINE + 150.0)
		rpm = lerpf(rpm, target, STEP * 12.0)
		sy.rpm = rpm
		sy.throttle = thr
		sy.speed = v
		sy.skid = 0.3 if spinning else 0.0
		_block(sy, buf)
		t += STEP
	return buf


func _surfaces(engine: float) -> PackedVector2Array:
	var sy := _synth("martello")
	sy.engine_level = engine
	var buf := PackedVector2Array()
	for surf in Surfaces.ORDER:
		var t := 0.0
		while t < 2.5:
			sy.surface = surf
			sy.rpm = 4200.0
			sy.throttle = 0.45
			sy.speed = 18.0
			sy.skid = clampf((t - 1.0) / 0.4, 0.0, 1.0) * 0.9
			_block(sy, buf)
			t += STEP
	return buf


func _impacts() -> PackedVector2Array:
	var buf := PackedVector2Array()
	for id in ["martello", "pardel"]:
		var sy := _synth(id)
		var events := {30: 0.3, 90: 0.8, 170: 1.2}
		for f in 260:
			if events.has(f):
				sy.crash(events[f])
			if f == 230:
				sy.land(0.8)
			sy.rpm = 1500.0
			sy.speed = 0.0
			_block(sy, buf)
	return buf


func _rain() -> PackedVector2Array:
	var sy := _synth("martello")
	sy.rain = true
	sy.surface = "wet"
	var buf := PackedVector2Array()
	for f in 300:
		sy.rpm = 1000.0 if f < 120 else 3800.0
		sy.throttle = 0.0 if f < 120 else 0.4
		sy.speed = 0.0 if f < 120 else 20.0
		_block(sy, buf)
	return buf


func _pivot() -> PackedVector2Array:
	var sy := _synth("pardel")
	var buf := PackedVector2Array()
	for f in 300:
		var t := f * STEP
		sy.throttle = 0.6 if t < 2.0 else 0.8
		sy.track_skid = 1.0 if t < 2.0 else 0.0
		sy.rpm = 3500.0 if t < 2.0 else 3000.0 + t * 400.0
		sy.speed = 0.0 if t < 2.0 else (t - 2.0) * 4.0
		_block(sy, buf)
	return buf


func _save(path: String, frames: PackedVector2Array) -> void:
	var data := PackedByteArray()
	data.resize(frames.size() * 4)
	for i in frames.size():
		data.encode_s16(i * 4, int(clampf(frames[i].x, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(frames[i].y, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(EngineSynth.RATE)
	wav.data = data
	wav.save_to_wav(path)
	print("wrote ", path)
