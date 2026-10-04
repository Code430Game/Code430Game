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
var override_brake: float = -1.0  # 0..1 for one physics frame (labs and scripted drives), like override_throttle

## Seconds the car may stay upside down (or below the world floor) before it is put back on the road.
@export var recover_after_s: float = 3.0
## Anything below this y is treated as having fallen out of the world.
@export var world_floor_y: float = -20.0

## Peer id of the player driving, 0 when empty. Only the driver's input reaches the car.
var driver_peer_id: int = 0

var _spawn: Transform3D
var _recover_timer: float = 0.0
## Called with the car when it needs recovering; the testbed sets this to place it on the nearest road.
var recover_callback: Callable


## Body tint for surface 0 of the generated mesh; set before _ready or call set_body_color.
@export var body_color: Color = Color(0.85, 0.25, 0.2)


## Emitted when the car hits something at `speed_mps` (closing speed estimate).
signal impacted(speed_mps: float)
var _last_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	_spawn = global_transform
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	var mesh_node := $Mesh as MeshInstance3D
	mesh_node.mesh = CarMesh.build(false)
	mesh_node.material_override = null
	mesh_node.position = Vector3(0.0, -0.12, 0.0)  # underside about 0.4 m over the road, like the old box
	set_body_color(body_color)


var _headlights: Array[SpotLight3D] = []


## Adds two spot headlights (off until set_headlights). `shadows` costs a shadow map each.
func add_headlights(shadows: bool) -> void:
	for x in [-0.6, 0.6]:
		var l := SpotLight3D.new()
		l.position = Vector3(x, 0.45, -2.1)
		l.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
		l.spot_range = 45.0
		l.spot_angle = 28.0
		l.light_energy = 0.0
		l.light_color = Color(1.0, 0.95, 0.85)
		l.shadow_enabled = shadows
		add_child(l)
		_headlights.append(l)


var _braking: bool = false


## Swaps the tail-light surface to the bright brake material while braking.
func set_braking(on: bool) -> void:
	if on == _braking:
		return
	_braking = on
	var mesh_node := $Mesh as MeshInstance3D
	if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 3:
		mesh_node.set_surface_override_material(3, CarMesh.brake_material() if on else null)


## Brightness of the headlights, 0 off to 1 full; follows the night factor.
func set_headlights(amount: float) -> void:
	for l in _headlights:
		l.light_energy = 6.0 * amount
		l.visible = amount > 0.02


## Paints the body (surface 0) with `color`; glass, trim and lights keep theirs.
func set_body_color(color: Color) -> void:
	body_color = color
	var mesh_node := $Mesh as MeshInstance3D
	if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
		mesh_node.set_surface_override_material(0, CarMesh.body_material(color))


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


func _on_body_entered(_body: Node) -> void:
	# The velocity before the contact resolved tells how hard we arrived.
	var closing := (_last_velocity - linear_velocity).length()
	impacted.emit(maxf(closing, _last_velocity.length() * 0.3))


func _physics_process(delta: float) -> void:
	_last_velocity = linear_velocity
	var driven := driver_peer_id == Players.LOCAL_PEER_ID
	var accel := Input.get_action_strength("accelerate") if driven else 0.0
	var brk := Input.get_action_strength("brake") if driven else 0.0
	var steer_in := Input.get_axis("move_right", "move_left") if driven else 0.0
	if override_throttle >= 0.0:
		accel = override_throttle
		steer_in = override_steer
		override_throttle = -1.0
	if override_brake >= 0.0:
		brk = override_brake
		override_brake = -1.0
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
	if driven and Input.is_action_pressed("handbrake"):
		brake = handbrake_force
	set_braking(brake > 0.0 and forward_speed() > -reverse_threshold_mps)
	if driven and Input.is_action_just_pressed("reset_vehicle"):
		_recover()
	var upside_down := global_basis.y.y < 0.0
	var fell_out := global_position.y < world_floor_y
	if fell_out:
		_recover()
	elif upside_down and linear_velocity.length() < 1.0:
		_recover_timer += delta
		if _recover_timer >= recover_after_s:
			_recover()
	else:
		_recover_timer = 0.0


func _recover() -> void:
	_recover_timer = 0.0
	if recover_callback.is_valid():
		recover_callback.call(self)
	else:
		reset_to_spawn()
