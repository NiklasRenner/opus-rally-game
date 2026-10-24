class_name EngineAudio
extends AudioStreamPlayer
## Plays the car's synthesised sound (EngineSynth), so the game needs no
## audio files. Copies the car's state into the synth every frame and spots
## gear changes and landings.

var car: RallyCar
var synth := EngineSynth.new()
var _playback: AudioStreamGeneratorPlayback
var _gear := 1
var _air := 0.0
var _fall := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = EngineSynth.RATE
	gen.buffer_length = 0.1
	stream = gen
	volume_db = -4.0
	synth.setup(car.spec)
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func crash(strength: float) -> void:
	synth.crash(strength)


func _process(delta: float) -> void:
	if _playback == null or car == null:
		return
	synth.rpm = car.rpm
	synth.throttle = car.brake if car.gear == -1 else car.throttle
	synth.speed = car.speed
	synth.skid = car.skid
	synth.surface = car.surface
	synth.rain = car.rain
	synth.track_skid = car._track_skid
	var grounded := false
	for w in car.wheels:
		grounded = grounded or w.grounded
	synth.grounded = grounded
	if not grounded:
		_air += delta
		_fall = maxf(_fall, -car.linear_velocity.y)
	else:
		if _air > 0.3 and _fall > 3.0:
			synth.land(_fall / 12.0)
		_air = 0.0
		_fall = 0.0
	if car.gear != _gear:
		if _gear >= 1 and car.gear >= 1:
			synth.shift(car.gear > _gear)
		_gear = car.gear
	var cam := get_viewport().get_camera_3d() as CameraRig
	synth.interior = cam != null and cam.mode_name() in ["HOOD", "BUMPER"]
	var frames := _playback.get_frames_available()
	if frames > 0:
		_playback.push_buffer(synth.render(frames))
