class_name EngineSynth
extends RefCounted
## Procedural vehicle sound: engine, turbo, gearbox, tyres per surface, wind,
## rain and impacts, synthesised sample by sample so the game needs no audio
## files. EngineAudio feeds it the car's state; tools/audio_preview.gd renders
## it offline to WAV files for listening and analysis.
##
## The engine plays a table of exhaust pulses once per engine cycle (two crank
## revolutions), so a pulse lasts a fixed crank angle like a real engine. The
## pulses then ring a few fixed resonances (exhaust pipe, body, intake) that
## stay put as the rpm moves, which is what makes it sound like an engine and
## not a buzzer. Each pulse gets a little random gain (more off the throttle
## and at idle), so a held note never drones.

const RATE := 22050.0
const TABLE := 2048

## Per-vehicle engine character.
## cyl, offsets (pulse timing error, fraction of a firing interval), amps (per
## cylinder), idle/red: rpm at game idle and at the limiter.
## on/off: [peak, sharpness] of the pulse on and off the throttle; knock: diesel clatter.
## top: highest harmonic kept (Hz), so revs never alias into whistles.
## r1/r2: exhaust resonances [Hz, Q, gain]; intake: [Hz, Q, gain] of the
## pulse-gated noise (rasp); body: lowpass cutoff [off, on] and gain.
## jitter: per-pulse gain wobble [on, off]. turbo: whistle gain (0 = none),
## bov: blow-off on lift, flutter: compressor flutter, crackle: overrun pops,
## antilag: how long pops keep going after a lift, shift_pop: bang on upshifts,
## whine: straight-cut gear whine, tracks: tank track clank.
const PROFILES := {
	# Delta-style 2.0 turbo four: raspy, chattering blow-off, lots of anti-lag
	"martello": {"cyl": 4, "offsets": [0.0, 0.02, -0.01, 0.015], "amps": [1.0, 0.9, 1.07, 0.94],
		"idle": 950.0, "red": 7800.0, "on": [0.13, 2.2], "off": [0.22, 1.6], "knock": 0.0, "top": 3200.0,
		"r1": [150.0, 2.2, 1.0], "r2": [540.0, 2.0, 0.5], "intake": [1500.0, 1.6, 0.4],
		"body": [600.0, 1800.0, 0.6], "jitter": [0.05, 0.22], "gain": 1.0,
		"turbo": 0.006, "whistle": [1400.0, 3000.0], "bov": 0.4, "flutter": 1.0,
		"crackle": 1.0, "antilag": 1.0, "shift_pop": 0.9, "whine": 0.005},
	# 555-style flat four: unequal exhaust pulses give the boxer burble
	"pleiad": {"cyl": 4, "offsets": [0.0, -0.13, 0.02, -0.11], "amps": [1.0, 0.82, 1.05, 0.86],
		"idle": 900.0, "red": 7600.0, "on": [0.14, 2.0], "off": [0.24, 1.5], "knock": 0.0, "top": 3000.0,
		"r1": [118.0, 2.2, 1.1], "r2": [420.0, 2.0, 0.5], "intake": [1300.0, 1.6, 0.35],
		"body": [500.0, 1600.0, 0.65], "jitter": [0.06, 0.26], "gain": 1.0,
		"turbo": 0.005, "whistle": [1300.0, 2800.0], "bov": 0.35, "flutter": 0.35,
		"crackle": 0.85, "antilag": 0.8, "shift_pop": 0.7, "whine": 0.004},
	# kit car: no turbo, revs higher, bright induction howl, the odd pop
	"balear": {"cyl": 4, "offsets": [0.0, 0.01, 0.0, -0.01], "amps": [1.0, 0.96, 1.03, 0.97],
		"idle": 1100.0, "red": 9000.0, "on": [0.11, 2.4], "off": [0.2, 1.7], "knock": 0.0, "top": 3600.0,
		"r1": [175.0, 2.2, 0.9], "r2": [680.0, 2.2, 0.55], "intake": [1800.0, 1.8, 0.5],
		"body": [700.0, 2200.0, 0.55], "jitter": [0.04, 0.18], "gain": 0.95,
		"turbo": 0.0, "whistle": [0.0, 0.0], "bov": 0.0, "flutter": 0.0,
		"crackle": 0.45, "antilag": 0.2, "shift_pop": 0.35, "whine": 0.006},
	# V10: uneven banks and lots of combustion rasp so it snarls rather than hums
	"f1": {"cyl": 10, "offsets": [0.0, 0.04, -0.03, 0.02, -0.05, 0.03, -0.02, 0.05, -0.04, 0.01],
		"amps": [1.0, 0.82, 1.1, 0.86, 1.04, 0.8, 1.08, 0.88, 1.02, 0.84], "idle": 4000.0, "red": 15500.0,
		"on": [0.12, 2.6], "off": [0.22, 1.8], "knock": 0.0, "top": 4500.0,
		"r1": [650.0, 1.8, 0.9], "r2": [1500.0, 1.8, 0.5], "intake": [2200.0, 1.5, 0.75],
		"body": [1000.0, 2400.0, 0.75], "jitter": [0.07, 0.18], "gain": 1.0,
		"turbo": 0.0, "whistle": [0.0, 0.0], "bov": 0.0, "flutter": 0.0,
		"crackle": 0.25, "antilag": 0.1, "shift_pop": 0.3, "whine": 0.0},
	# twin-turbo V12 diesel: deep and slow, the banks firing unevenly for a
	# lumpy throb, heavy track rumble and a clank per track link
	"tank": {"cyl": 12, "offsets": [0.0, 0.03, -0.02, 0.05, 0.0, -0.04, 0.02, 0.0, -0.03, 0.04, 0.01, -0.02],
		"amps": [1.0, 0.72, 1.1, 0.76, 1.04, 0.7, 1.08, 0.8, 0.98, 0.74, 1.12, 0.78],
		"idle": 520.0, "red": 2200.0, "on": [0.08, 2.6], "off": [0.13, 2.0], "knock": 0.2, "top": 1600.0,
		"r1": [55.0, 1.8, 1.6], "r2": [190.0, 2.0, 0.7], "intake": [800.0, 1.6, 0.35],
		"body": [250.0, 650.0, 0.9], "jitter": [0.1, 0.25], "gain": 1.15,
		"turbo": 0.004, "whistle": [1500.0, 2600.0], "bov": 0.0, "flutter": 0.0,
		"crackle": 0.0, "antilag": 0.0, "shift_pop": 0.0, "whine": 0.0, "tracks": 1.0},
}

## Tyre sound per surface: roll (rumble gain, lowpass Hz), squeal (gain, Hz),
## grain (crunch impacts per metre, Hz), hiss (spray), swish (soft-ground
## slide), splash (water), clack (plank joints).
const SURFACE_SOUND := {
	"asphalt": {"roll": [0.05, 500.0], "squeal": [0.16, 1050.0], "grain": [0.0, 0.0], "hiss": 0.0, "swish": 0.0, "splash": 0.0, "clack": 0.0},
	"gravel": {"roll": [0.09, 900.0], "squeal": [0.0, 0.0], "grain": [9.0, 2300.0], "hiss": 0.012, "swish": 0.12, "splash": 0.0, "clack": 0.0},
	"wet": {"roll": [0.05, 600.0], "squeal": [0.06, 800.0], "grain": [0.0, 0.0], "hiss": 0.12, "swish": 0.02, "splash": 0.0, "clack": 0.0},
	"ice": {"roll": [0.025, 350.0], "squeal": [0.025, 1500.0], "grain": [2.5, 2600.0], "hiss": 0.012, "swish": 0.0, "splash": 0.0, "clack": 0.0},
	"grass": {"roll": [0.07, 300.0], "squeal": [0.0, 0.0], "grain": [1.0, 900.0], "hiss": 0.0, "swish": 0.25, "splash": 0.0, "clack": 0.0},
	"mud": {"roll": [0.08, 260.0], "squeal": [0.0, 0.0], "grain": [1.5, 600.0], "hiss": 0.0, "swish": 0.25, "splash": 0.03, "clack": 0.0},
	"ford": {"roll": [0.03, 300.0], "squeal": [0.0, 0.0], "grain": [0.0, 0.0], "hiss": 0.05, "swish": 0.03, "splash": 0.2, "clack": 0.0},
	"wood": {"roll": [0.08, 420.0], "squeal": [0.1, 950.0], "grain": [0.0, 0.0], "hiss": 0.0, "swish": 0.0, "splash": 0.0, "clack": 0.35},
}

# --------------------------------------------------------------------------- inputs
## Set these before each render(); EngineAudio copies them from the car.
var rpm := 1000.0  # the car's rpm (RallyCar.IDLE_RPM .. REDLINE)
var throttle := 0.0
var speed := 0.0  # m/s
var skid := 0.0  # 0..1
var surface := "asphalt"
var grounded := true
var rain := false
var track_skid := 0.0  # tank pivoting on the spot
var interior := false  # bonnet / bumper camera: less exhaust, more intake and road
var engine_level := 1.0  # previews mute the engine to hear the tyres

const GAME_IDLE := 1000.0
const GAME_RED := 8000.0

# --------------------------------------------------------------------------- state
var _p: Dictionary
var _lv_on: Array[PackedFloat32Array] = []  # band-limited copies, LEVELS of them
var _lv_off: Array[PackedFloat32Array] = []
var _cyl := 4
var _seed := 12345

var _ph := 0.0
var _inc := 0.0
var _gain := 0.0
var _ld := 0.0
var _pk := -1
var _pg := 1.0
var _wobble := 0.0
var _lift_t := 10.0
var _was_on := false
var _cut := 0.0  # shift ignition cut, seconds left
var _lim_t := 0.0
var _boost := 0.0
var _kick := 0.0  # extra crackle after a downshift
var _int := 0.0
var _time := 0.0

# filter states (lp, bp pairs)
var _s := PackedFloat32Array()
var _wh_ph := 0.0
var _tb_ph := 0.0
var _fl_ph := 0.0
var _kl_ph := 0.0
var _cl_ph := 0.0
var _th_ph := 0.0
var _dc_x := 0.0
var _dc_y := 0.0

# one-shot envelopes
var _bov := 0.0
var _pop := 0.0
var _pop_f := 0.3
var _genv := 0.0
var _kenv := 0.0
var _cenv := 0.0
var _denv := 0.0
var _tenv := 0.0
var _thump := 0.0
var _th_f := 90.0
var _crunch := 0.0
var _crunch_f := [0.3, 0.5]
var _tinkle := 0.0
var _heavy := false

# smoothed tyre channel gains
var _g := {"roll": 0.0, "roll_f": 500.0, "squeal": 0.0, "squeal_f": 1000.0, "grain": 0.0, "grain_f": 2000.0,
	"hiss": 0.0, "swish": 0.0, "splash": 0.0, "clack": 0.0}


## Pick the vehicle: a profile by car id, else by type. `pitch` tunes cars
## without a profile of their own.
func setup(spec: Dictionary) -> void:
	var id: String = spec.get("id", "")
	var type: String = spec.get("type", "car")
	var pitch: float = spec.get("stats", {}).get("pitch", 1.0)
	if PROFILES.has(id):
		_p = PROFILES[id].duplicate(true)
	elif type == "f1" or type == "tank":
		_p = PROFILES[type].duplicate(true)
	else:
		_p = PROFILES["martello"].duplicate(true)
		_p["idle"] *= pitch
		_p["red"] *= pitch
	_heavy = type == "tank"
	_cyl = _p["cyl"]
	_lv_on = _band_limit(_table(_p["on"][0], _p["on"][1], 1.0))
	_lv_off = _band_limit(_table(_p["off"][0], _p["off"][1], 2.2))
	_s.resize(48)
	_s.fill(0.0)
	_seed = hash(id) & 0x7fffffff


## Exhaust pulse train for one engine cycle. Pulses rise fast and decay
## (blowdown); `spread` scales the per-cylinder amplitude differences.
func _table(peak: float, sharp: float, spread: float) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(TABLE + 1)
	t.fill(0.0)
	var offsets: Array = _p["offsets"]
	var amps: Array = _p["amps"]
	var knock: float = _p["knock"]
	var span := int(float(TABLE) / _cyl)
	for k in _cyl:
		var start := int((k + float(offsets[k % offsets.size()])) * span)
		var amp := 1.0 + (float(amps[k % amps.size()]) - 1.0) * spread
		for j in span:
			var x := float(j) / span
			var y := pow(x / peak, sharp) * exp(sharp * (1.0 - x / peak))
			y *= 0.5 + 0.5 * cos(PI * x)
			if knock > 0.0:
				y += knock * exp(-x * 9.0) * sin(x * TAU * 7.0)
			t[posmod(start + j, TABLE)] += y * amp
	var mean := 0.0
	for i in TABLE:
		mean += t[i]
	mean /= TABLE
	var top := 0.0
	for i in TABLE:
		t[i] -= mean
		top = maxf(top, absf(t[i]))
	for i in TABLE:
		t[i] /= top
	t[TABLE] = t[0]
	return t


## Copies of a cycle table keeping fewer and fewer harmonics (512, 362,
## 256 ... 4, half an octave apart, tapered at the top), so render() can pick
## one that stays under the profile's `top` at any rpm. Playing the raw table
## fast would fold its upper harmonics back down as whistles that fall as
## the revs rise.
const LEVELS := 15


func _band_limit(t: PackedFloat32Array) -> Array[PackedFloat32Array]:
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(TABLE)
	im.resize(TABLE)
	for i in TABLE:
		re[i] = t[i]
		im[i] = 0.0
	_fft(re, im, false)
	var out: Array[PackedFloat32Array] = []
	for lv in LEVELS:
		var top := 512.0 * pow(2.0, -lv * 0.5)
		var r2 := PackedFloat64Array()
		var i2 := PackedFloat64Array()
		r2.resize(TABLE)
		i2.resize(TABLE)
		r2.fill(0.0)
		i2.fill(0.0)
		for h in range(1, int(top) + 1):
			var x := (h - 0.6 * top) / (0.4 * top)
			var w := 1.0 if x <= 0.0 else 0.5 + 0.5 * cos(PI * minf(x, 1.0))
			r2[h] = re[h] * w
			i2[h] = im[h] * w
			r2[TABLE - h] = re[TABLE - h] * w
			i2[TABLE - h] = im[TABLE - h] * w
		_fft(r2, i2, true)
		var lt := PackedFloat32Array()
		lt.resize(TABLE + 1)
		for i in TABLE:
			lt[i] = r2[i] / TABLE
		lt[TABLE] = lt[0]
		out.append(lt)
	return out


static func _fft(re: PackedFloat64Array, im: PackedFloat64Array, inverse: bool) -> void:
	var n := re.size()
	var j := 0
	for i in range(1, n):
		var bit := n >> 1
		while (j & bit) != 0:
			j ^= bit
			bit >>= 1
		j |= bit
		if i < j:
			var tr := re[i]
			re[i] = re[j]
			re[j] = tr
			var ti := im[i]
			im[i] = im[j]
			im[j] = ti
	var size := 2
	while size <= n:
		var ang := (TAU if inverse else -TAU) / size
		var half := size >> 1
		for k in half:
			var wr := cos(ang * k)
			var wi := sin(ang * k)
			for st in range(0, n, size):
				var a := st + k
				var b := a + half
				var xr := re[b] * wr - im[b] * wi
				var xi := re[b] * wi + im[b] * wr
				re[b] = re[a] - xr
				im[b] = im[a] - xi
				re[a] += xr
				im[a] += xi
		size <<= 1


static func _svf(fc: float) -> float:
	return 2.0 * sin(PI * minf(fc, RATE * 0.16) / RATE)


static func _pole(fc: float) -> float:
	return 1.0 - exp(-TAU * fc / RATE)


## Gear changed. Upshifts cut the ignition for a moment (and bang on rally
## cars); downshifts blip and set off a few overrun pops.
func shift(up: bool) -> void:
	if up:
		_cut = 0.07
		if _p["shift_pop"] > 0.0 and _ld > 0.5 and randf() < 0.85:
			_trigger_pop(_p["shift_pop"])
	else:
		_kick = maxf(_kick, 0.6)


func crash(strength: float) -> void:
	strength = clampf(strength, 0.0, 1.5)
	_thump = maxf(_thump, strength * 0.9)
	_th_f = 70.0 if _heavy else 95.0
	_crunch = maxf(_crunch, strength * 0.8)
	if _heavy:
		_crunch_f = [_svf(randf_range(220.0, 420.0)), _svf(randf_range(600.0, 900.0))]
	else:
		_crunch_f = [_svf(randf_range(500.0, 900.0)), _svf(randf_range(1300.0, 2600.0))]
	if strength > 0.45 and not _heavy:
		_tinkle = maxf(_tinkle, strength)


## Touchdown after a jump: a suspension thump, no crunch.
func land(strength: float) -> void:
	_thump = maxf(_thump, clampf(strength, 0.0, 1.0) * 0.7)
	_th_f = 60.0 if _heavy else 75.0


func _trigger_pop(strength: float) -> void:
	_pop = maxf(_pop, strength * randf_range(0.6, 1.0))
	_pop_f = _svf(randf_range(250.0, 750.0))


func render(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(n)
	if n <= 0 or _p.is_empty():
		return out
	var p := _p
	var dt := float(n) / RATE
	_time += dt

	# ---- block controls (smoothed per block, ramped per sample)
	var rpm_n := clampf((rpm - GAME_IDLE) / (GAME_RED - GAME_IDLE), 0.0, 1.03)
	_wobble = lerpf(_wobble, randf_range(-1.0, 1.0) * (0.006 if rpm_n < 0.1 else 0.0025), 0.08)
	var vrpm: float = lerpf(p["idle"], p["red"], rpm_n) * (1.0 + _wobble)
	_ld += (throttle - _ld) * minf(dt * 14.0, 1.0)
	var ld := _ld
	var on := throttle > 0.2
	if on:
		_lift_t = 0.0
	else:
		_lift_t += dt
	# turbo spools up with load and revs, dumps through the blow-off on a lift
	var boost_target := throttle * clampf((rpm_n - 0.2) / 0.5, 0.0, 1.0)
	_boost = move_toward(_boost, boost_target, dt * (1.1 if boost_target > _boost else 2.5))
	if _was_on and not on and _boost > 0.35 and p["bov"] > 0.0:
		_bov = maxf(_bov, _boost * p["bov"])
		_boost *= 0.4
	_was_on = on
	var crackle: float = p["crackle"] * smoothstep(0.3, 0.65, rpm_n) * (1.0 - ld)
	crackle *= exp(-_lift_t / (0.35 + 1.6 * p["antilag"])) + _kick
	if speed < 3.0:
		crackle *= 0.3
	_kick = maxf(_kick - dt * 0.8, 0.0)
	var cut := 1.0
	if _cut > 0.0:
		_cut -= dt
		cut = 0.3
	if rpm >= GAME_RED - 30.0 and throttle > 0.5:
		_lim_t += dt
		if fmod(_lim_t, 0.075) < 0.03:
			cut = 0.25
	else:
		_lim_t = 0.0
	_int = move_toward(_int, 1.0 if interior else 0.0, dt * 4.0)

	var new_inc := vrpm / 120.0 / RATE  # engine cycles (two revs) per sample
	var dinc := (new_inc - _inc) / n
	var new_gain: float = engine_level * p["gain"] * (0.42 + 0.58 * ld) * (0.65 + 0.35 * rpm_n) * cut
	var dgain := (new_gain - _gain) / n
	var jit: float = lerpf(p["jitter"][1], p["jitter"][0], ld) * (1.6 if rpm_n < 0.08 else 1.0)

	var r1: Array = p["r1"]
	var r2: Array = p["r2"]
	var ri: Array = p["intake"]
	var body: Array = p["body"]
	var f1 := _svf(r1[0]); var q1 := 1.0 / float(r1[1])
	var f2 := _svf(r2[0]); var q2 := 1.0 / float(r2[1])
	var f3 := _svf(ri[0]); var q3 := 1.0 / float(ri[1])
	var fb := _pole(lerpf(body[0], body[1], ld) * (0.8 + 0.4 * rpm_n))
	var exhaust := 1.0 - 0.3 * _int
	var w1: float = r1[2] * q1 * exhaust
	var w2: float = r2[2] * q2 * exhaust
	var w3: float = ri[2] * q3 * (0.35 + 0.65 * ld) * (0.25 + 0.75 * rpm_n) * (1.0 + 0.6 * _int)
	var wb: float = body[2]

	var tb_amp: float = p["turbo"] * _boost * _boost * (0.4 + 0.6 * ld)
	var wl: Array = p["whistle"]
	var tb_inc: float = lerpf(wl[0], wl[1], _boost) / RATE
	var bov_decay := exp(-1.0 / (0.28 * RATE))
	var fl_inc: float = 17.0 / RATE
	var flutter: float = p["flutter"]
	var f4 := _svf(2700.0); var q4 := 1.0 / 1.3
	var pop_decay := exp(-1.0 / (0.022 * RATE))
	var q5 := 1.0 / 1.6

	# straight-cut gears whine with road speed, louder off the throttle
	var wheel_rps := speed / (TAU * Cars.WHEEL_RADIUS)
	var wh_amp: float = p["whine"] * clampf(speed / 25.0, 0.0, 1.0) * (1.0 - 0.45 * ld)
	var wh_inc := wheel_rps * 4.4 * 11.0 / RATE

	# tank tracks: a clank per track link, rattling together at speed
	var tracks: float = p.get("tracks", 0.0)
	var kl_amp := tracks * clampf(speed / 3.0, 0.0, 1.0) * (0.12 + 0.1 * clampf(speed / 15.0, 0.0, 1.0))
	var kl_inc := speed / 0.17 / RATE
	var kl_decay := exp(-1.0 / (0.006 * RATE))
	var f6 := _svf(700.0); var q6 := 1.0 / 4.0
	var sq_tr := tracks * track_skid * 0.08

	# ---- tyres: crossfade channel gains toward the surface's
	var sd: Dictionary = SURFACE_SOUND.get(surface, SURFACE_SOUND["grass"])
	var sp_n := clampf(speed / 30.0, 0.0, 1.3)
	var on_ground := 1.0 if grounded else 0.0
	var g := _g
	var k := minf(dt * 10.0, 1.0)
	var road := 1.0 + 0.25 * _int
	var tank_tyre := 0.35 if _heavy else 1.0
	g["roll"] += (sd["roll"][0] * sqrt(sp_n) * on_ground * road - g["roll"]) * k
	g["roll_f"] += (sd["roll"][1] * (0.7 + 0.5 * sp_n) - g["roll_f"]) * k
	g["squeal"] += (sd["squeal"][0] * skid * on_ground * tank_tyre - g["squeal"]) * k
	g["squeal_f"] += (sd["squeal"][1] * (0.9 + 0.25 * skid) - g["squeal_f"]) * k
	g["grain"] += (sd["grain"][0] * on_ground * (0.3 + 1.5 * skid) - g["grain"]) * k
	g["grain_f"] += (maxf(sd["grain"][1], 300.0) - g["grain_f"]) * k
	g["hiss"] += ((sd["hiss"] + (0.03 if rain else 0.0)) * sp_n * on_ground - g["hiss"]) * k
	g["swish"] += (sd["swish"] * (skid + 0.15 * sp_n) * on_ground - g["swish"]) * k
	g["splash"] += (sd["splash"] * minf(sp_n * 2.0, 1.0) * on_ground - g["splash"]) * k
	g["clack"] += (sd["clack"] * on_ground - g["clack"]) * k
	var roll_amp: float = g["roll"]
	var fr := _pole(g["roll_f"])
	var sq_amp: float = g["squeal"]
	var sq_wob := 1.0 + 0.04 * sin(_time * 2.1) + randf_range(-0.02, 0.02)
	var f8 := _svf(g["squeal_f"] * sq_wob); var q8 := 1.0 / 8.0
	var gr_p: float = g["grain"] * speed / RATE  # crunch hits per sample
	var gr_amp := 0.5 if gr_p > 0.0 else 0.0
	var f9 := _svf(g["grain_f"]); var q9 := 1.0 / 2.0
	var g_decay := exp(-1.0 / (0.003 * RATE))
	var hiss_amp: float = g["hiss"]
	var fh := _pole(2500.0)
	var sw_amp: float = g["swish"]
	var fs1 := _pole(180.0); var fs2 := _pole(900.0)
	var spl_amp: float = g["splash"]
	var f10 := _svf(randf_range(500.0, 1300.0)); var q10 := 1.0 / 2.5
	var cl_amp: float = g["clack"] * clampf(speed / 6.0, 0.0, 1.0)
	var cl_inc := speed / 0.6 / RATE
	var wind_amp := 0.05 * sp_n * sp_n * (1.0 + 0.3 * _int)
	var fw := _pole(650.0)

	# ---- rain on the body
	var dr_p := (35.0 / RATE) if rain else 0.0
	var rain_hiss := 0.018 if rain else 0.0
	var f11 := _svf(2900.0); var q11 := 1.0 / 5.0
	var d_decay := exp(-1.0 / (0.004 * RATE))

	# ---- impacts
	var th_decay := exp(-1.0 / ((0.3 if _heavy else 0.2) * RATE))
	var th_inc := _th_f / RATE
	var cr_decay := exp(-1.0 / ((0.35 if _heavy else 0.18) * RATE))
	var cr1: float = _crunch_f[0]
	var cr2: float = _crunch_f[1]
	var qc := 1.0 / (14.0 if _heavy else 6.0)
	var tk_decay := exp(-1.0 / (0.35 * RATE))
	var f13 := _svf(2600.0); var q13 := 1.0 / 8.0
	var t_decay := exp(-1.0 / (0.012 * RATE))

	# ---- copy state into locals for the hot loop
	var hmax: float = p["top"] / maxf(vrpm / 120.0, 1.0)
	var lv := clampi(int(ceil(2.0 * log(512.0 / hmax) / log(2.0))), 0, LEVELS - 1)
	var t_on: PackedFloat32Array = _lv_on[lv]
	var t_off: PackedFloat32Array = _lv_off[lv]
	var cyl := float(_cyl)
	var s := _s
	var ph := _ph
	var inc := _inc
	var gain := _gain
	var rs := _seed
	var pk := _pk
	var pg := _pg
	var bov := _bov
	var pop := _pop
	var pop_f := _pop_f
	var genv := _genv
	var kenv := _kenv
	var cenv := _cenv
	var denv := _denv
	var tenv := _tenv
	var thump := _thump
	var crunch := _crunch
	var tinkle := _tinkle
	var wh_ph := _wh_ph
	var tb_ph := _tb_ph
	var fl_ph := _fl_ph
	var kl_ph := _kl_ph
	var cl_ph := _cl_ph
	var th_ph := _th_ph
	var dc_x := _dc_x
	var dc_y := _dc_y
	var l1 := s[0]; var b1 := s[1]; var l2 := s[2]; var b2 := s[3]; var l3 := s[4]; var b3 := s[5]
	var lb := s[6]; var lb2 := s[7]; var l4 := s[8]; var b4 := s[9]; var l5 := s[10]; var b5 := s[11]
	var l6 := s[12]; var b6 := s[13]; var l7 := s[14]; var l8 := s[15]; var b8 := s[16]
	var l9 := s[17]; var b9 := s[18]; var hs := s[19]; var rl1 := s[20]; var rl2 := s[21]
	var sw1 := s[22]; var sw2 := s[23]; var l10 := s[24]; var b10 := s[25]; var wd := s[26]
	var l11 := s[27]; var b11 := s[28]; var lc1 := s[29]; var bc1 := s[30]; var lc2 := s[31]; var bc2 := s[32]
	var l13 := s[33]; var b13 := s[34]; var ltr := s[35]; var btr := s[36]; var lsp := s[37]
	var ld_off := 1.0 - ld
	var fm := _pole(5200.0)
	var m1 := s[38]
	var m2 := s[39]
	var rb := s[40]
	var pop_on := crackle * 0.16

	for i in n:
		# ------------------------------------------------ engine
		ph += inc
		inc += dinc
		if ph >= 1.0:
			ph -= 1.0
		var pos := ph * TABLE
		var ti := int(pos)
		var frac := pos - ti
		var a := t_on[ti]
		var c := t_off[ti]
		var e := (a + (t_on[ti + 1] - a) * frac) * ld + (c + (t_off[ti + 1] - c) * frac) * ld_off
		var kk := int(ph * cyl)
		if kk != pk:
			pk = kk
			rs = (rs * 1103515245 + 12345) & 0x7fffffff
			pg = 1.0 + jit * (rs / 1073741823.5 - 1.0)
			if pop_on > 0.0:
				rs = (rs * 1103515245 + 12345) & 0x7fffffff
				if rs / 2147483647.0 < pop_on:
					rs = (rs * 1103515245 + 12345) & 0x7fffffff
					pop = maxf(pop, 0.35 + 0.65 * rs / 2147483647.0)
					pop_f = 0.07 + 0.13 * rs / 2147483647.0
		e *= pg
		rs = (rs * 1103515245 + 12345) & 0x7fffffff
		var nz := rs / 1073741823.5 - 1.0
		l1 += f1 * b1
		var h := e - l1 - q1 * b1
		b1 += f1 * h
		l2 += f2 * b2
		h = e - l2 - q2 * b2
		b2 += f2 * h
		var rin := nz * e if e > 0.0 else 0.0
		l3 += f3 * b3
		h = rin - l3 - q3 * b3
		b3 += f3 * h
		lb += fb * (e - lb)
		lb2 += fb * (lb - lb2)
		var eng := (lb2 * wb + b1 * w1 + b2 * w2 + b3 * w3) * gain
		gain += dgain
		if tb_amp > 0.0002:
			tb_ph += tb_inc
			if tb_ph >= 1.0:
				tb_ph -= 1.0
			eng += sin(tb_ph * TAU) * tb_amp
		if bov > 0.0005:
			bov *= bov_decay
			fl_ph += fl_inc
			if fl_ph >= 1.0:
				fl_ph -= 1.0
			var fl := 1.0 - flutter * (0.5 + 0.5 * cos(fl_ph * TAU)) * 0.8
			l4 += f4 * b4
			h = nz * bov * fl - l4 - q4 * b4
			b4 += f4 * h
			eng += b4 * 0.12
		if pop > 0.0005:
			pop *= pop_decay
			l5 += pop_f * b5
			h = nz * pop - l5 - q5 * b5
			b5 += pop_f * h
			eng += (b5 * 0.35 + l5 * 0.25)
		if wh_amp > 0.0002:
			wh_ph += wh_inc
			if wh_ph >= 1.0:
				wh_ph -= 1.0
			var sw := sin(wh_ph * TAU)
			eng += (sw + 0.3 * (1.0 - 2.0 * sw * sw)) * wh_amp
		if kl_amp > 0.0002:
			kl_ph += kl_inc
			if kl_ph >= 1.0:
				kl_ph -= 1.0
				rs = (rs * 1103515245 + 12345) & 0x7fffffff
				kenv = 0.55 + 0.45 * rs / 2147483647.0
			kenv *= kl_decay
			l6 += f6 * b6
			h = nz * kenv - l6 - q6 * b6
			b6 += f6 * h
			l7 += 0.02 * (kenv - l7)
			rb += 0.012 * (nz - rb)
			eng += (b6 * 0.18 + l7 * 9.0 + rb * 2.5) * kl_amp
		if sq_tr > 0.0005:
			ltr += 0.32 * btr
			h = nz - ltr - 0.06 * btr
			btr += 0.32 * h
			eng += btr * 0.06 * sq_tr

		# ------------------------------------------------ tyres, wind, weather
		rl1 += fr * (nz - rl1)
		rl2 += fr * (rl1 - rl2)
		var tyre := rl2 * roll_amp * 2.0
		if sq_amp > 0.0003:
			l8 += f8 * b8
			h = nz - l8 - q8 * b8
			b8 += f8 * h
			tyre += b8 * sq_amp * 0.9
		if gr_p > 0.0:
			rs = (rs * 1103515245 + 12345) & 0x7fffffff
			if rs / 2147483647.0 < gr_p:
				rs = (rs * 1103515245 + 12345) & 0x7fffffff
				genv = 0.3 + 0.7 * rs / 2147483647.0
			genv *= g_decay
			l9 += f9 * b9
			h = nz * genv - l9 - q9 * b9
			b9 += f9 * h
			tyre += (b9 + l9 * 0.4) * gr_amp
		if hiss_amp > 0.0002:
			hs += fh * (nz - hs)
			tyre += (nz - hs) * hiss_amp
		if sw_amp > 0.0003:
			sw1 += fs2 * (nz - sw1)
			sw2 += fs1 * (sw1 - sw2)
			tyre += (sw1 - sw2) * sw_amp
		if spl_amp > 0.0003:
			lsp += 0.0004 * ((nz if nz > 0.3 else 0.0) - lsp)
			l10 += f10 * b10
			h = nz * (0.4 + 8.0 * lsp) - l10 - q10 * b10
			b10 += f10 * h
			tyre += b10 * q10 * spl_amp * 2.0
		if cl_amp > 0.0003:
			cl_ph += cl_inc
			if cl_ph >= 1.0:
				cl_ph -= 1.0
				cenv = 1.0
			cenv *= 0.9985
			tyre += cenv * cenv * sin(cenv * 40.0) * cl_amp * 0.3
		wd += fw * (nz - wd)
		tyre += wd * wind_amp
		if dr_p > 0.0:
			rs = (rs * 1103515245 + 12345) & 0x7fffffff
			if rs / 2147483647.0 < dr_p:
				rs = (rs * 1103515245 + 12345) & 0x7fffffff
				denv = 0.3 + 0.7 * rs / 2147483647.0
			denv *= d_decay
			l11 += f11 * b11
			h = nz * denv - l11 - q11 * b11
			b11 += f11 * h
			tyre += b11 * q11 * 0.5 + nz * rain_hiss * (0.5 + 0.5 * hs)

		# ------------------------------------------------ impacts
		var bang := 0.0
		if thump > 0.0005:
			thump *= th_decay
			th_ph += th_inc * (0.55 + 0.45 * thump)
			if th_ph >= 1.0:
				th_ph -= 1.0
			bang += sin(th_ph * TAU) * thump
		if crunch > 0.0005:
			crunch *= cr_decay
			var x := nz * crunch
			lc1 += cr1 * bc1
			h = x - lc1 - qc * bc1
			bc1 += cr1 * h
			lc2 += cr2 * bc2
			h = x - lc2 - qc * bc2
			bc2 += cr2 * h
			bang += (bc1 + bc2) * qc * 2.2 + x * 0.12
		if tinkle > 0.001:
			tinkle *= tk_decay
			rs = (rs * 1103515245 + 12345) & 0x7fffffff
			if rs / 2147483647.0 < tinkle * 0.0012:
				tenv = 0.6
			tenv *= t_decay
			l13 += f13 * b13
			h = nz * tenv - l13 - q13 * b13
			b13 += f13 * h
			bang += b13 * q13 * 1.5

		# ------------------------------------------------ mix
		var y := eng + tyre + bang
		m1 += fm * (y - m1)
		m2 += fm * (m1 - m2)
		y = m2
		dc_y = y - dc_x + 0.997 * dc_y
		dc_x = y
		y = clampf(dc_y, -3.0, 3.0)
		y = y * (27.0 + y * y) / (27.0 + 9.0 * y * y)
		out[i] = Vector2(y, y)

	# ---- write state back
	_ph = ph
	_inc = new_inc
	_gain = new_gain
	_seed = rs
	_pk = pk
	_pg = pg
	_bov = bov
	_pop = pop
	_pop_f = pop_f
	_genv = genv
	_kenv = kenv
	_cenv = cenv
	_denv = denv
	_tenv = tenv
	_thump = thump
	_crunch = crunch
	_tinkle = tinkle
	_wh_ph = wh_ph
	_tb_ph = tb_ph
	_fl_ph = fl_ph
	_kl_ph = kl_ph
	_cl_ph = cl_ph
	_th_ph = th_ph
	_dc_x = dc_x
	_dc_y = dc_y
	var st := [l1, b1, l2, b2, l3, b3, lb, lb2, l4, b4, l5, b5, l6, b6, l7, l8, b8, l9, b9, hs, rl1, rl2,
		sw1, sw2, l10, b10, wd, l11, b11, lc1, bc1, lc2, bc2, l13, b13, ltr, btr, lsp, m1, m2, rb]
	for j in st.size():
		s[j] = st[j]
	_s = s
	return out
