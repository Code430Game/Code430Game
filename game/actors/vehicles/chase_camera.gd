class_name ChaseCamera
extends Camera3D
## Follows a target from behind with smoothing. Right stick orbits temporarily.

@export var target: Node3D
@export var distance_m: float = 7.5
@export var height_m: float = 3.0
@export var look_height_m: float = 1.0
@export var position_smoothing: float = 6.0
@export var orbit_speed_rad_s: float = 2.5
@export var orbit_return_speed: float = 3.0

var _orbit: float = 0.0


func _process(delta: float) -> void:
	if target == null:
		return
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if absf(look.x) > 0.0:
		_orbit += -look.x * orbit_speed_rad_s * delta
	else:
		_orbit = move_toward(_orbit, 0.0, orbit_return_speed * delta)
	var back := target.global_basis.z.rotated(Vector3.UP, _orbit)
	back.y = 0.0
	back = back.normalized()
	var desired := target.global_position + back * distance_m + Vector3.UP * height_m
	global_position = global_position.lerp(desired, clampf(position_smoothing * delta, 0.0, 1.0))
	look_at(target.global_position + Vector3.UP * look_height_m, Vector3.UP)
