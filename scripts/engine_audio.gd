class_name EngineAudio
extends AudioStreamPlayer
## Tiny synthesised engine + tyre noise, so the prototype needs no audio
## files. Pitch follows rpm; skids and impacts add filtered noise.

const RATE := 22050.0

var car: RallyCar
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase2 := 0.0
var _noise := 0.0
var _crash := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	stream = gen
	volume_db = -8.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func crash(strength: float) -> void:
	_crash = maxf(_crash, strength)


func _process(delta: float) -> void:
	if _playback == null or car == null:
		return
	var frames := _playback.get_frames_available()
	var freq := car.rpm / 60.0 * 2.0 * car.stat("pitch")  # 4-cylinder: two firing pulses per rev
	var eng_load := 0.35 + car.throttle * 0.65
	var skid := car.skid
	for i in frames:
		_phase = fmod(_phase + freq / RATE, 1.0)
		_phase2 = fmod(_phase2 + freq * 0.5 / RATE, 1.0)
		var saw := _phase * 2.0 - 1.0
		var pulse := 1.0 if _phase < 0.25 else -0.3
		var sub := sin(_phase2 * TAU)
		var eng := (saw * 0.35 + pulse * 0.35 * eng_load + sub * 0.3) * (0.18 + 0.12 * eng_load)
		_noise = lerpf(_noise, randf_range(-1.0, 1.0), 0.35)
		var tyre := _noise * skid * 0.16
		var bang := randf_range(-1.0, 1.0) * _crash * 0.5
		var s := eng + tyre + bang
		_playback.push_frame(Vector2(s, s))
		_crash = maxf(_crash - 3.0 / RATE, 0.0)
