class_name AmbienceAudio
extends Node
## City hum: filtered noise whose level follows how much traffic is near the player.

var traffic: TrafficManager
var _player: AudioStreamPlayer
var _noise_state: Array = [0x2545F491]
var _lp1: float = 0.0
var _lp2: float = 0.0
var _level: float = 0.3
var rain: float = 0.0  # 0..1 precipitation from the weather: a hiss over the hum
var _hp: float = 0.0
var muted: bool = false


func _ready() -> void:
	_player = Synth.make_player("Ambience", -18.0)
	add_child(_player)
	_player.play()


## Ambience level 0..1 for a number of cars within earshot.
static func level_for(nearby_cars: int) -> float:
	return clampf(0.25 + float(nearby_cars) / 40.0, 0.25, 1.0)


func _process(delta: float) -> void:
	if muted:
		return
	var nearby := 0
	if traffic != null:
		for a in traffic.agents:
			if a.anchor_dist < 120.0:
				nearby += 1
	_level = lerpf(_level, level_for(nearby), minf(delta * 2.0, 1.0))
	var pb: AudioStreamGeneratorPlayback = _player.get_stream_playback()
	if pb == null:
		return
	var frames := pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(frames)
	var rain_gain := rain * 0.22
	for i in range(frames):
		var n := Synth.noise(_noise_state)
		_lp1 += (n - _lp1) * 0.02
		_lp2 += (_lp1 - _lp2) * 0.02
		var s := _lp2 * 4.0 * _level
		if rain_gain > 0.0:
			# Rain: the noise minus a gentle low-pass, so a bright steady hiss sits over the hum.
			_hp += (n - _hp) * 0.3
			s += (n - _hp) * rain_gain
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)
