class_name VehicleAudio
extends Node
## Engine, tyre, impact and horn voices for one car, fed each frame from its speed and throttle.
## Attach under the car; call `impact(speed)` from a collision. The horn sounds while the
## driver holds `horn`; it sits on the car itself so it is heard from there.

var car: VehicleBody3D
var _engine: AudioStreamPlayer
var _tyres: AudioStreamPlayer
var _impact: AudioStreamPlayer
var horn: Horn
var _phase: float = 0.0
var _phase2: float = 0.0
var _noise_state: Array = [0x9E3779B9]
var _tyre_lp: float = 0.0
var _impact_left: float = 0.0  # seconds of thump remaining
var _impact_gain: float = 0.0
var muted: bool = false


func _ready() -> void:
	_engine = Synth.make_player("SFX", -10.0)
	_tyres = Synth.make_player("SFX", -14.0)
	_impact = Synth.make_player("SFX", -2.0)
	for p in [_engine, _tyres, _impact]:
		add_child(p)
		p.play()
	horn = Horn.new()
	horn.name = "Horn"
	_move_horn.call_deferred()  # the car may be busy setting up its children right now


## Moves the voices to `new_car` (the local player got into it): reparents under it, follows its
## collisions, and restarts any voice that stopped while nobody was driving. One VehicleAudio
## serves the local player, whichever car they drive.
func attach(new_car: VehicleBody3D) -> void:
	if car != null and car != new_car and car.impacted.is_connected(impact):
		car.impacted.disconnect(impact)
	car = new_car
	if get_parent() != new_car:
		if get_parent() != null:
			get_parent().remove_child(self)
		new_car.add_child(self)
	if horn != null and horn.get_parent() != new_car:
		horn.sounding = false
		_move_horn.call_deferred()
	if not new_car.impacted.is_connected(impact):
		new_car.impacted.connect(impact)
	for p in [_engine, _tyres, _impact]:
		if p != null and not p.playing:
			p.play()


## Puts the horn on the current car (or keeps it here when there is none yet).
func _move_horn() -> void:
	var target: Node = car if is_instance_valid(car) else self
	if horn.get_parent() == target:
		return
	if horn.get_parent() != null:
		horn.get_parent().remove_child(horn)
	target.add_child(horn)


## Starts a thump whose loudness follows the collision speed.
func impact(speed_mps: float) -> void:
	var g := Synth.impact_gain(speed_mps)
	if g <= 0.0:
		return
	_impact_gain = maxf(_impact_gain, g)
	_impact_left = 0.25 + 0.2 * g


func _process(delta: float) -> void:
	if car == null or muted:
		if horn != null:
			horn.sounding = false
		return
	horn.sounding = _driven() and Input.is_action_pressed("horn")
	# The engine and tyres are the driver's voices: silent while nobody is in the car, or the
	# idle note followed the player on foot across the whole city (the generator players are
	# not positional). Impacts still sound when something hits the parked car.
	if _driven():
		var speed := absf(car.forward_speed())
		var throttle := clampf(absf(car.engine_force) / maxf(car.engine_force_max, 1.0), 0.0, 1.0)
		_fill_engine(speed, throttle)
		_fill_tyres(speed)
	_fill_impact(delta)


## True when the engine voice is producing sound this frame (tests).
func engine_running() -> bool:
	return car != null and not muted and _driven()


func _driven() -> bool:
	return car.driver_peer_id == Players.LOCAL_PEER_ID


func _fill_engine(speed: float, throttle: float) -> void:
	var pb: AudioStreamGeneratorPlayback = _engine.get_stream_playback()
	if pb == null:
		return
	var hz := Synth.engine_hz(speed, throttle)
	var step := TAU * hz / Synth.MIX_RATE
	var amp := 0.25 + 0.45 * throttle + 0.1 * clampf(speed / 30.0, 0.0, 1.0)
	var frames := pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in range(frames):
		_phase += step
		_phase2 += step * 0.5
		# A reedy pulse: saw plus half-rate square, a dash of noise for grit.
		var saw := fmod(_phase / TAU, 1.0) * 2.0 - 1.0
		var sq := 1.0 if fmod(_phase2 / TAU, 1.0) < 0.5 else -1.0
		var s := (saw * 0.6 + sq * 0.3 + Synth.noise(_noise_state) * 0.1) * amp
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)
	if _phase > 1000.0 * TAU:
		_phase = fmod(_phase, TAU)
	if _phase2 > 1000.0 * TAU:
		_phase2 = fmod(_phase2, TAU)


func _fill_tyres(speed: float) -> void:
	var pb: AudioStreamGeneratorPlayback = _tyres.get_stream_playback()
	if pb == null:
		return
	var gain := Synth.tyre_gain(speed)
	var frames := pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(frames)
	var cutoff := 0.04 + 0.2 * gain  # brighter hiss at speed
	for i in range(frames):
		_tyre_lp += (Synth.noise(_noise_state) - _tyre_lp) * cutoff
		var s := _tyre_lp * gain * 1.5
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)


func _fill_impact(delta: float) -> void:
	var pb: AudioStreamGeneratorPlayback = _impact.get_stream_playback()
	if pb == null:
		return
	var frames := pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(frames)
	var dt := 1.0 / Synth.MIX_RATE
	var lp := 0.0
	for i in range(frames):
		var s := 0.0
		if _impact_left > 0.0:
			lp += (Synth.noise(_noise_state) - lp) * 0.12  # low thud
			var env := clampf(_impact_left / 0.3, 0.0, 1.0)
			s = lp * env * env * _impact_gain * 3.0
			_impact_left -= dt
		else:
			_impact_gain = 0.0
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)
	if _impact_left <= 0.0:
		_impact_left = 0.0
	delta = delta  # unused beyond keeping the signature uniform
