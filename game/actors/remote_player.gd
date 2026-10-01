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

var _body: MeshInstance3D
var _car: AnimatableBody3D
var _car_mesh: MeshInstance3D
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
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CarMesh.WIDTH_M, 1.3, CarMesh.LENGTH_M)
	shape.shape = box
	shape.position.y = 0.75
	_car.add_child(shape)
	_car_mesh = MeshInstance3D.new()
	_car_mesh.mesh = CarMesh.build(true)
	_car_mesh.set_surface_override_material(0, CarMesh.body_material(tint))
	_car_mesh.position.y = CarMesh.GROUND_LIFT_M
	_car.add_child(_car_mesh)
	_car.top_level = true
	add_child(_car)
	_car.visible = false


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
	else:
		_body.mesh = CharacterMesh.build(profile)
		_body.position.y = 0.0


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
	_car.visible = driving
	car_target = car_t if driving else Transform3D(Basis(), Vector3(0, -1000, 0))
	_car.global_transform = car_target
