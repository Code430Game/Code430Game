class_name RemotePlayer
extends Node3D
## Another peer's character and car as seen on this machine: a capsule and a car replica
## driven by network state, interpolated a little behind the newest sample. The car replica
## is an AnimatableBody3D so local physics bumps against it.

const INTERP_DELAY_S := 0.1

var peer_id: int = 0
var color: Color = Color.WHITE
var driving: bool = false
## Latest interpolated car transform; the replica body follows it on the next physics tick.
var car_target: Transform3D = Transform3D.IDENTITY

var _body: MeshInstance3D  # capsule stand-in until a profile arrives
var _rig: CharacterRig = null
var _last_pos: Vector3 = Vector3.INF
var _car: AnimatableBody3D
var _car_mesh: MeshInstance3D
var _car_shape: CollisionShape3D
var horn: Horn  # on the replica car, sounding while the peer holds theirs
var _vehicle_id: String = ""
var _car_color: Color = Color.WHITE
var _samples: Array = []  # [{"t": float, "driving": bool, "body": Transform3D, "car": Transform3D}]
var _clock: float = 0.0


func setup(id: int, tint: Color, profile: Dictionary = {}) -> void:
	peer_id = id
	color = tint
	_body = MeshInstance3D.new()
	add_child(_body)
	apply_profile(profile)
	_car = AnimatableBody3D.new()
	_car.sync_to_physics = true
	_car_shape = CollisionShape3D.new()
	_car.add_child(_car_shape)
	_car_mesh = MeshInstance3D.new()
	_car.add_child(_car_mesh)
	horn = Horn.new()
	_car.add_child(horn)
	_car.top_level = true
	add_child(_car)
	_car.visible = false
	set_vehicle(VehicleCatalogue.default_player, tint)


## Builds the replica car as `vehicle_id` in `car_color` (only when either changed).
func set_vehicle(vehicle_id: String, car_color: Color) -> void:
	if vehicle_id == _vehicle_id and car_color == _car_color:
		return
	_vehicle_id = vehicle_id
	_car_color = car_color
	var e := VehicleCatalogue.entry(vehicle_id)
	_car_mesh.mesh = VehicleMesh.build(e, VehicleMesh.Lod.LOD0, true, VehicleCatalogue.livery(vehicle_id))
	_car_mesh.set_surface_override_material(0, VehicleMesh.body_material(car_color))
	var box := BoxShape3D.new()
	box.size = VehicleMesh.box_size(e)
	_car_shape.shape = box
	_car_shape.position.y = box.size.y * 0.5 + 0.1


## The vehicle the replica currently shows.
func vehicle_id() -> String:
	return _vehicle_id


## Wears the peer's character; an empty profile keeps the tinted capsule stand-in.
func apply_profile(profile: Dictionary) -> void:
	if profile.is_empty():
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.8
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		capsule.material = mat
		_body.mesh = capsule
		_body.position.y = 0.9
		_body.visible = not driving
		if _rig != null:
			_rig.queue_free()
			_rig = null
	else:
		_body.mesh = null
		if _rig == null:
			_rig = CharacterRig.new()
			_rig.profile = profile
			add_child(_rig)
		else:
			_rig.apply_profile(profile)
		_rig.visible = not driving


## Position of whatever this peer controls, for streaming and traffic anchors.
func controlled_position() -> Vector3:
	return _car.global_position if driving else global_position


## Records a network sample: character transform, car transform, and whether the peer drives.
func push_state(is_driving: bool, body_t: Transform3D, car_t: Transform3D) -> void:
	_samples.append({"t": _clock, "driving": is_driving, "body": body_t, "car": car_t})
	while _samples.size() > 6:
		_samples.pop_front()


func _process(delta: float) -> void:
	_clock += delta
	if _samples.is_empty():
		return
	var target := _clock - INTERP_DELAY_S
	var a: Dictionary = _samples[0]
	var b: Dictionary = _samples[_samples.size() - 1]
	for i in range(_samples.size() - 1):
		if float(_samples[i + 1]["t"]) >= target:
			a = _samples[i]
			b = _samples[i + 1]
			break
	var span := float(b["t"]) - float(a["t"])
	var u := clampf((target - float(a["t"])) / span, 0.0, 1.0) if span > 0.0 else 1.0
	driving = bool(b["driving"])
	var body_t: Transform3D = (a["body"] as Transform3D).interpolate_with(b["body"], u)
	var car_t: Transform3D = (a["car"] as Transform3D).interpolate_with(b["car"], u)
	global_transform = body_t
	_body.visible = not driving
	if _rig != null:
		_rig.visible = not driving
		var speed: float = 0.0 if _last_pos == Vector3.INF or delta <= 0.0 else global_position.distance_to(_last_pos) / delta
		_rig.advance(delta, speed)
		_last_pos = global_position
	_car.visible = driving
	car_target = car_t if driving else Transform3D(Basis(), Vector3(0, -1000, 0))
	_car.global_transform = car_target
