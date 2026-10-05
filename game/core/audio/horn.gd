class_name Horn
extends Node3D
## A car horn: two detuned square tones a minor third apart, with a short attack and release,
## from a positional player so a co-op peer hears it from the car. Set `sounding` each frame.

const LOW_HZ := 370.0
const HIGH_HZ := 440.0
const ATTACK_S := 0.015
const RELEASE_S := 0.06

var sounding: bool = false
var _player: AudioStreamPlayer3D
var _phase_low: float = 0.0
var _phase_high: float = 0.0
var _env: float = 0.0  # 0 silent .. 1 full


func _ready() -> void:
	_player = Synth.make_player_3d("SFX", -4.0, 12.0)
	add_child(_player)
	_player.play()


## True while the horn is audible (pressed, or still releasing).
func audible() -> bool:
	return sounding or _env > 0.0


## One sample of the two tones at full level, for the oscillator phases given.
static func sample(phase_low: float, phase_high: float) -> float:
	var a := 1.0 if fmod(phase_low / TAU, 1.0) < 0.5 else -1.0
	var b := 1.0 if fmod(phase_high / TAU, 1.0) < 0.5 else -1.0
	return (a + b) * 0.25


func _process(_delta: float) -> void:
	var pb := _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	if not audible():
		return  # let the buffer run dry: silence costs nothing
	var frames := pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(frames)
	var dt := 1.0 / Synth.MIX_RATE
	var step_low := TAU * LOW_HZ * dt
	var step_high := TAU * HIGH_HZ * dt
	for i in range(frames):
		if sounding:
			_env = minf(_env + dt / ATTACK_S, 1.0)
		else:
			_env = maxf(_env - dt / RELEASE_S, 0.0)
		_phase_low += step_low
		_phase_high += step_high
		var s := sample(_phase_low, _phase_high) * _env
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)
	_phase_low = fmod(_phase_low, TAU)
	_phase_high = fmod(_phase_high, TAU)
