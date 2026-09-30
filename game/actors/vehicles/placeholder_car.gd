extends VehicleBody3D
## Placeholder car: arcade-ish tuning on Godot's VehicleBody3D (Jolt).
## Right trigger accelerates, left trigger brakes (or reverses from a stop),
## left stick steers, RB is the handbrake. Tunables are exported.
##
## Convention: the car's forward is -Z like every other Godot node. Measured on
## Godot 4.7, VehicleBody3D pushes toward +Z for a positive engine force, so the
## force is negated here rather than flipping the model, camera, and spawn.

@export var engine_force_max: float = 4500.0
@export var reverse_force_max: float = 2500.0
@export var brake_force_max: float = 80.0
@export var handbrake_force: float = 160.0
@export var steer_max_rad: float = 0.6
@export var steer_speed_rad_s: float = 3.0
## Steering lock shrinks linearly with speed until this fraction remains at `steer_fade_speed_mps`.
@export var steer_min_fraction: float = 0.35
@export var steer_fade_speed_mps: float = 30.0
@export var reverse_threshold_mps: float = 0.5
## Engine force fades to zero as forward speed approaches this.
@export var top_speed_kph: float = 150.0
## External driver input (autodrive). When set, replaces player input for one physics frame.
var override_throttle: float = -1.0
var override_steer: float = 0.0

var _spawn: Transform3D


func _ready() -> void:
	_spawn = global_transform


## Speed along the car's forward axis in m/s (positive = forward).
func forward_speed() -> float:
	return -linear_velocity.dot(global_basis.z)


## Speed in km/h, unsigned.
func speed_kph() -> float:
	return linear_velocity.length() * 3.6


## Sets where reset_to_spawn returns the car to.
func set_spawn(t: Transform3D) -> void:
	_spawn = t


## Puts the car back at the spawn transform with no velocity.
func reset_to_spawn() -> void:
	global_transform = _spawn
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	var accel := Input.get_action_strength("accelerate")
	var brk := Input.get_action_strength("brake")
	var steer_in := Input.get_axis("move_right", "move_left")
	if override_throttle >= 0.0:
		accel = override_throttle
		steer_in = override_steer
		override_throttle = -1.0
	var speed := absf(forward_speed())
	var fade := clampf(speed / steer_fade_speed_mps, 0.0, 1.0)
	var lock := steer_max_rad * lerpf(1.0, steer_min_fraction, fade)
	steering = move_toward(steering, steer_in * lock, steer_speed_rad_s * delta)
	if brk > 0.0 and forward_speed() < reverse_threshold_mps and accel == 0.0:
		engine_force = reverse_force_max * brk  # positive force = +Z = backwards
		brake = 0.0
	else:
		var headroom := clampf(1.0 - forward_speed() * 3.6 / top_speed_kph, 0.0, 1.0)
		engine_force = -engine_force_max * accel * headroom  # negative force = -Z = forward
		brake = brake_force_max * brk
	if Input.is_action_pressed("handbrake"):
		brake = handbrake_force
	if Input.is_action_just_pressed("reset_vehicle"):
		reset_to_spawn()
