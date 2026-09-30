extends Node3D
## Empty testbed: ground, sky, light, and a free camera driven by the controller.
## Exists so the project boots on the Deck and the presets can be seen.

const MOVE_SPEED_MPS := 12.0
const SPRINT_MULTIPLIER := 3.0
const LOOK_SPEED_RAD := 2.0

@onready var _camera: Camera3D = $Camera3D


func _process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	_camera.rotate_y(-look.x * LOOK_SPEED_RAD * delta)
	_camera.rotate_object_local(Vector3.RIGHT, -look.y * LOOK_SPEED_RAD * delta)
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed := MOVE_SPEED_MPS * (SPRINT_MULTIPLIER if Input.is_action_pressed("sprint") else 1.0)
	var direction := (_camera.global_basis * Vector3(move.x, 0.0, move.y))
	_camera.global_position += direction * speed * delta
	if Input.is_action_just_pressed("pause"):
		get_tree().quit()
