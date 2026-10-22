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
var override_hold: bool = false  # handbrake on for one physics frame: stopped and staying put (brake alone reverses when still)

## Seconds the car may stay upside down (or below the world floor) before it is put back on the road.
@export var recover_after_s: float = 3.0
## Anything below this y is treated as having fallen out of the world.
@export var world_floor_y: float = -20.0

## Peer id of the player driving, 0 when empty. Only the driver's input reaches the car.
var driver_peer_id: int = 0
var _base_grip: float = 2.5  # the catalogue entry's tyre grip; weather scales it (add-weather)
var _grip_factor: float = 1.0

var _spawn: Transform3D
var _recover_timer: float = 0.0
var _reset_hold_s: float = 0.0  # seconds the reset button has been held; -1 once it fired
## Called with the car when it needs recovering; the testbed sets this to place it on the nearest road.
var recover_callback: Callable


## Body tint for surface 0 of the generated mesh; set before _ready or call set_body_color.
@export var body_color: Color = Color(0.85, 0.25, 0.2)
## VehicleCatalogue entry the car is built from; set before _ready, or call apply_entry.
## Empty: the catalogue's default player car.
@export var vehicle_id: String = ""
## Radio station this car is tuned to (a station id or Radio.OFF); empty until it is first driven
## or handed one (Radio.pick_for_car), and kept when the player gets out.
var radio_station: String = ""
const COM_HEIGHT_FRACTION := 0.07  # of body height: 0.10 m for a sedan, 0.23 m for a box truck
## Length of the current body, for the chase camera's framing.
var length_m: float = 4.6


## Emitted when the car hits something at `speed_mps` (closing speed estimate).
signal impacted(speed_mps: float)
var _last_velocity: Vector3 = Vector3.ZERO
## Health, dents, smoke and a wreck's fire (add-vehicle-and-building-damage).
var damage: VehicleDamage
var _base_mesh: ArrayMesh  # the undented body; dents go on a copy
var _height_m: float = 1.5
var _width_m: float = 1.8
const BODY_DULL := [0.0, 0.1, 0.18, 0.26, 0.32]  # how much each damage stage darkens the paint
const SHELL_COLOR := Color(0.07, 0.06, 0.055)  # a burnt-out wreck


func _ready() -> void:
	_spawn = global_transform
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	damage = VehicleDamage.new()
	damage.name = "Damage"
	add_child(damage)
	damage.stage_changed.connect(func(_s: int) -> void: _refresh_damage_looks())
	damage.exploded.connect(func(_at: Vector3, _r: float) -> void: _refresh_damage_looks())
	apply_entry(vehicle_id if vehicle_id != "" else VehicleCatalogue.default_player)


var _headlights: Array[SpotLight3D] = []


## Adds two spot headlights (off until set_headlights). `shadows` costs a shadow map each.
func add_headlights(shadows: bool) -> void:
	for x in [-0.6, 0.6]:
		var l := SpotLight3D.new()
		l.position = Vector3(x, 0.8, -length_m * 0.5)
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
	if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 3 and not (damage != null and damage.lights_out.has("rear")):
		mesh_node.set_surface_override_material(3, VehicleMesh.brake_material() if on else null)


## Tyre grip as a fraction of the catalogue's (rain 0.8, snow 0.55 from the weather table).
func set_grip_factor(factor: float) -> void:
	var f := clampf(factor, 0.05, 1.5)
	if is_equal_approx(f, _grip_factor):
		return
	_grip_factor = f
	for name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var w := get_node_or_null(name) as VehicleWheel3D
		if w != null:
			w.wheel_friction_slip = _base_grip * _grip_factor


func grip_factor() -> float:
	return _grip_factor


## Brightness of the headlights, 0 off to 1 full; follows the night factor.
func set_headlights(amount: float) -> void:
	var out := damage != null and damage.lights_out.has("front")
	for l in _headlights:
		l.light_energy = 6.0 * amount
		l.visible = amount > 0.02 and not out


## Paints the body (surface 0) with `color`; glass, trim and lights keep theirs.
func set_body_color(color: Color) -> void:
	body_color = color
	var mesh_node := $Mesh as MeshInstance3D
	if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
		mesh_node.set_surface_override_material(0, VehicleMesh.body_material(_damaged_color(color)))


## The paint as damage shows it: dulled by stage, a burnt shell once the fire is through.
func _damaged_color(color: Color) -> Color:
	if damage == null:
		return color
	if damage.fire == VehicleDamage.Fire.SHELL:
		return SHELL_COLOR
	return color.darkened(BODY_DULL[damage.stage])


## The body after a hit: the dented copy (or the plain mesh once mended), the paint, the lights.
func _refresh_damage_looks() -> void:
	var mesh_node := $Mesh as MeshInstance3D
	if _base_mesh == null:
		return
	var want: Mesh = _base_mesh
	if not damage.dents.is_empty():
		want = VehicleMesh.dented(_base_mesh, damage.dents, VehicleDamage.tun("dent_radius_m"))
	mesh_node.mesh = want
	set_body_color(body_color)
	var front_out := damage.lights_out.has("front")
	if mesh_node.mesh.get_surface_count() > 3:
		mesh_node.set_surface_override_material(2, VehicleMesh.broken_light_material() if front_out else null)
		var rear_out := damage.lights_out.has("rear")
		mesh_node.set_surface_override_material(3, VehicleMesh.broken_light_material() if rear_out else (VehicleMesh.brake_material() if _braking else null))
	for l in _headlights:
		if front_out:
			l.visible = false


## Builds the car from a catalogue entry: body mesh, wheel layout and radius, collision box,
## mass and handling. The body's origin is on the ground under its centre, like the mesh's.
func apply_entry(id: String) -> void:
	var e: Dictionary = VehicleCatalogue.entry(id)
	vehicle_id = str(e.get("id", id))
	var d: Dictionary = e["dims"]
	var wr := float(d["wheel_radius_m"])
	var height := float(d["height_m"])
	length_m = float(d["length_m"])
	mass = float(e["mass_kg"])
	engine_force_max = float(e["engine_force"])
	reverse_force_max = engine_force_max * 0.55
	brake_force_max = float(e["brake_force"])
	handbrake_force = brake_force_max * 2.0
	top_speed_kph = float(e["top_speed_kph"])
	steer_max_rad = float(e["steer_max_rad"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# Arcade-low centre of mass that grows with the body, so tall vans and trucks lean more in a
	# hard turn than a sedan without rolling: at a realistic height (wheel radius + 0.15, about
	# 0.5 m) the grip let every class roll over at full lock and 60. Entries may set their own.
	center_of_mass = Vector3(0.0, float(d.get("com_height_m", height * COM_HEIGHT_FRACTION)), 0.0)
	var mesh_node := $Mesh as MeshInstance3D
	_base_mesh = VehicleMesh.build(e, VehicleMesh.Lod.LOD0, false, VehicleCatalogue.livery(vehicle_id))
	mesh_node.mesh = _base_mesh
	_height_m = height
	_width_m = float(d["width_m"])
	if damage != null:
		damage.length_m = length_m
		damage.height_m = height
	mesh_node.material_override = null
	mesh_node.transform = Transform3D.IDENTITY
	for i in range(4):
		mesh_node.set_surface_override_material(i, null)
	_braking = false
	var clearance := wr * 0.6
	var box := BoxShape3D.new()
	box.size = Vector3(float(d["width_m"]), height - clearance - 0.1, length_m)
	var shape := $Shape as CollisionShape3D
	shape.shape = box
	shape.transform = Transform3D(Basis(), Vector3(0.0, clearance + box.size.y * 0.5, 0.0))
	var rest := 0.2
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = wr
	wheel_mesh.bottom_radius = wr
	wheel_mesh.height = clampf(wr * 0.68, 0.2, 0.32)
	wheel_mesh.material = VehicleMesh.dark_material()
	var positions := VehicleMesh.wheel_positions(e)
	var names := ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]
	_base_grip = float(e["grip"])
	for i in range(4):
		var w := get_node(names[i]) as VehicleWheel3D
		# The attach point sits so the tyre touches y = 0 with the suspension a little compressed.
		w.position = Vector3(positions[i].x, wr + rest - 0.05, positions[i].z)
		w.wheel_radius = wr
		w.wheel_rest_length = rest
		w.wheel_friction_slip = _base_grip * _grip_factor
		w.suspension_max_force = mass * 9.8 * 1.5  # per wheel: the box truck must not bottom out
		var wm := w.get_child(0) as MeshInstance3D
		wm.mesh = wheel_mesh
		if w.is_inside_tree():
			# A wheel reads its mount point when it enters the tree: re-enter so the move counts.
			remove_child(w)
			add_child(w)
	var seat := get_node_or_null("Seat") as Marker3D
	if seat != null:
		seat.position = Vector3(-float(d["width_m"]) * 0.22, wr + 0.45, -length_m * 0.5 + float(d.get("cabin_start_m", 1.7)) + 0.6)
	for l in _headlights:
		l.position.z = -length_m * 0.5
		l.position.y = minf(height * 0.5, 1.0)
	set_body_color(body_color)
	if damage != null and not damage.dents.is_empty():
		_refresh_damage_looks()


## Speed along the car's forward axis in m/s (positive = forward).
func forward_speed() -> float:
	return -linear_velocity.dot(global_basis.z)


## A player may get in: not a burning wreck (a stalled one, in clean, they may).
func can_enter() -> bool:
	return damage == null or not (damage.is_wrecked() and damage.burns())


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
	var change := _last_velocity - linear_velocity
	var closing := change.length()
	var speed := maxf(closing, _last_velocity.length() * 0.3)
	impacted.emit(speed)
	if damage != null:
		# The hit is on the side the car was thrown away from.
		var dir := change if closing > 0.5 else _last_velocity
		damage.crash(speed, hit_point(global_basis.inverse() * dir, _width_m, length_m, _height_m))


## Where on a `width` x `length` body a hit from direction `local_dir` (the car's frame) lands:
## where that direction leaves the body's footprint, a little under half its height.
static func hit_point(local_dir: Vector3, width: float, length: float, height: float) -> Vector3:
	var d := Vector2(local_dir.x, local_dir.z)
	if d.length() < 0.001:
		return Vector3(0.0, height, 0.0)  # from above: the roof
	var t := 1.0 / maxf(absf(d.x) / (width * 0.5), absf(d.y) / (length * 0.5))
	return Vector3(d.x * t, height * 0.45, d.y * t)


var _speed_limit: float = INF
var _speed_limit_until_ms: int = 0


## For `seconds`, keeps the car from going faster than `max_mps` or the speed it had just
## before this physics step, whichever is higher: a crash can slow it, never launch it.
func limit_speed(max_mps: float, seconds: float) -> void:
	_speed_limit = maxf(max_mps, _last_velocity.length() + 2.0)
	_speed_limit_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _speed_limit < INF:
		if Time.get_ticks_msec() > _speed_limit_until_ms:
			_speed_limit = INF
		elif state.linear_velocity.length() > _speed_limit:
			state.linear_velocity = state.linear_velocity.limit_length(_speed_limit)


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
		var power := damage.power_factor() if damage != null else 1.0
		var headroom := clampf(1.0 - forward_speed() * 3.6 / maxf(top_speed_kph * power, 1.0), 0.0, 1.0)
		engine_force = -engine_force_max * accel * headroom * power  # negative force = -Z = forward
		brake = brake_force_max * brk
	if driven and Input.is_action_pressed("handbrake"):
		brake = handbrake_force
	if override_hold:
		engine_force = 0.0
		brake = handbrake_force
		override_hold = false
	if damage != null and damage.is_wrecked():
		engine_force = 0.0  # dead: it rolls to a stop
		brake = brake_force_max * 0.6
	set_braking(brake > 0.0 and forward_speed() > -reverse_threshold_mps)
	_step_reset_hold(driven and Input.is_action_pressed("reset_vehicle"), delta)
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


## Reset only fires once its button has been held for the hold time (R3 tap looks behind); it
## then waits for a release so a long hold resets once.
func _step_reset_hold(held: bool, delta: float) -> void:
	if not held:
		_reset_hold_s = 0.0
		return
	if _reset_hold_s < 0.0:
		return  # already reset on this hold
	_reset_hold_s += delta
	if _reset_hold_s >= Controls.hold_s():
		_reset_hold_s = -1.0
		_recover()


## How far the reset hold has got, 0..1, for the HUD ring (0 when not held or already done).
func reset_progress() -> float:
	return clampf(_reset_hold_s / Controls.hold_s(), 0.0, 1.0) if _reset_hold_s > 0.0 else 0.0


func _recover() -> void:
	_recover_timer = 0.0
	if damage != null and damage.is_wrecked():
		if damage.burns():
			return  # a burning wreck stays where it is
		damage.mend()  # a stalled wreck (clean) is mended by a reset; other damage stays
	if recover_callback.is_valid():
		recover_callback.call(self)
	else:
		reset_to_spawn()
