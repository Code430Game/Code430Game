class_name Player
extends CharacterBody3D
## On-foot player: camera-relative walk/run/jump, orbit camera on a spring arm,
## and entering/leaving vehicles. Registered in the Players autoload by peer id.
## Forward is -Z. The car keeps rolling when left with nobody in it.

signal entered_vehicle(vehicle: VehicleBody3D)
signal exited_vehicle(vehicle: VehicleBody3D)
## Interact next to a traffic car with no player vehicle nearer: the scene turns it into a vehicle.
signal take_vehicle_requested(traffic_body: Node3D)

@export var config: PlayerConfig
@export var peer_id: int = 1
## The look this body is built from (CharacterProfile); set before adding to the tree, or
## call apply_profile. Empty: the default profile.
var profile: Dictionary = {}

@onready var _pivot: Node3D = $CameraPivot
@onready var _arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _body_mesh: Node3D = $Mesh
var _rig: CharacterRig = null
@onready var _shape: CollisionShape3D = $Shape

var vehicle: VehicleBody3D = null
## Called with this player when it wants to enter a vehicle; the scene decides which camera to use.
var _yaw: float = 0.0
## True while look behind is held: the camera faces back over the shoulder.
var look_behind: bool = false
## While true (aim held with a weapon) the camera pulls in over the right shoulder and the
## character faces where it looks.
var aiming: bool = false
const AIM_DISTANCE_SHARE := 0.45
const AIM_SHOULDER_M := 0.6
var _pitch: float = 0.0
var _mouse_look: Vector2 = Vector2.ZERO  # accumulated mouse motion this frame, radians
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	if config == null:
		config = load("res://actors/player/player_config.tres")
	floor_max_angle = deg_to_rad(config.floor_max_angle_deg)
	_arm.spring_length = config.camera_distance_m
	_pivot.position.y = config.camera_height_m
	_pitch = deg_to_rad(config.camera_default_pitch_deg)
	_apply_camera_angles()
	apply_profile(profile)
	Players.register(peer_id, self)


## Rebuilds the body from a CharacterProfile dictionary.
func apply_profile(p: Dictionary) -> void:
	profile = CharacterProfile.normalise(p)
	if _body_mesh == null:
		return
	if _rig == null:
		_rig = CharacterRig.new()
		_rig.profile = profile
		_body_mesh.add_child(_rig)
	else:
		_rig.apply_profile(profile)


func _exit_tree() -> void:
	if Players.local() == self:
		Players.unregister(peer_id)


## The body the player is controlling right now: the vehicle when driving, else self.
func controlled_body() -> Node3D:
	return vehicle if vehicle != null else self


func is_driving() -> bool:
	return vehicle != null


## Makes this player's camera the active one.
## The player's own camera (weapons aim through it).
func camera() -> Camera3D:
	return _camera


func activate_camera() -> void:
	_camera.current = true


func _physics_process(delta: float) -> void:
	if is_driving():
		global_position = vehicle.global_position  # keep the body with the car for minimap and distance checks
		if Input.is_action_just_pressed("interact") and peer_id == Players.LOCAL_PEER_ID:
			try_exit_vehicle()
		return
	_orbit(delta)
	_move(delta)
	if _rig != null:
		_rig.advance(delta, Vector3(velocity.x, 0.0, velocity.z).length())
	if Input.is_action_just_pressed("interact") and peer_id == Players.LOCAL_PEER_ID:
		var car := nearest_vehicle()
		if car != null:
			enter_vehicle(car)
		else:
			var traffic_body := nearest_traffic_car()
			if traffic_body != null:
				take_vehicle_requested.emit(traffic_body)


func _orbit(delta: float) -> void:
	look_behind = Input.is_action_pressed("look_behind") and not get_tree().paused
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	_yaw -= look.x * config.camera_orbit_speed_rad_s * delta + _mouse_look.x
	_pitch = clampf(_pitch + look.y * config.camera_orbit_speed_rad_s * delta + _mouse_look.y, deg_to_rad(config.camera_pitch_min_deg), deg_to_rad(config.camera_pitch_max_deg))
	_mouse_look = Vector2.ZERO
	var k := clampf(10.0 * delta, 0.0, 1.0)
	_arm.spring_length = lerpf(_arm.spring_length, config.camera_distance_m * (AIM_DISTANCE_SHARE if aiming else 1.0), k)
	_arm.position.x = lerpf(_arm.position.x, AIM_SHOULDER_M if aiming else 0.0, k)
	if aiming:
		_body_mesh.rotation.y = lerp_angle(_body_mesh.rotation.y, _yaw, k)
	_apply_camera_angles()


## Mouse look while the mouse is captured (the scene captures it on the desktop when on foot).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and peer_id == Players.LOCAL_PEER_ID:
		var m := event as InputEventMouseMotion
		_mouse_look += m.relative * config.mouse_look_rad_per_px


func _apply_camera_angles() -> void:
	_pivot.rotation = Vector3(-_pitch, _yaw + (PI if look_behind else 0.0), 0.0)


func _move(delta: float) -> void:
	var wading := is_wading()
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and not wading:
		velocity.y = config.jump_velocity(_gravity)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_forward := -_pivot.global_basis.z
	if look_behind:
		cam_forward = -cam_forward  # glancing back does not turn the stick round
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := Vector3(-cam_forward.z, 0.0, cam_forward.x)
	var wish := (cam_right * input.x + cam_forward * -input.y)
	var speed := config.run_speed_mps if Input.is_action_pressed("sprint") else config.walk_speed_mps
	if wading:
		speed *= config.wade_speed_factor
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish.length_squared() > 0.0:
		wish = wish.normalized()
		horizontal = horizontal.move_toward(wish * speed, config.acceleration_mps2 * delta)
		var target_yaw := atan2(-wish.x, -wish.z)
		_body_mesh.rotation.y = lerp_angle(_body_mesh.rotation.y, target_yaw, clampf(config.turn_speed_rad_s * delta, 0.0, 1.0))
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, config.deceleration_mps2 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()


## True while standing on a wading floor (chest deep in water): slower, no jumping.
func is_wading() -> bool:
	if not is_on_floor():
		return false
	for i in range(get_slide_collision_count()):
		var collider := get_slide_collision(i).get_collider()
		if collider is Node and (collider as Node).is_in_group("water"):
			return true
	return false


## Closest vehicle with a seat within enter range, or null.
func nearest_vehicle() -> VehicleBody3D:
	var best: VehicleBody3D = null
	var best_d := config.enter_range_m
	for node in get_tree().get_nodes_in_group("vehicles"):
		if not (node is VehicleBody3D):
			continue
		var seat := node.get_node_or_null("Seat") as Node3D
		var seat_pos := seat.global_position if seat != null else (node as Node3D).global_position
		var d := seat_pos.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


## Closest traffic car body (group "traffic", with a live agent) within enter range, or null.
func nearest_traffic_car() -> Node3D:
	var best: Node3D = null
	var best_d := config.enter_range_m + 1.0  # the body centre sits further in than a seat
	for node in get_tree().get_nodes_in_group("traffic"):
		if not (node is Node3D) or node.get("agent") == null:
			continue
		var d := (node as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


## Gets in: the body is hidden and frozen, the car takes this peer's input.
func enter_vehicle(car: VehicleBody3D) -> void:
	if car.get("driver_peer_id") != null and car.driver_peer_id != 0 and car.driver_peer_id != peer_id:
		return
	vehicle = car
	car.driver_peer_id = peer_id
	_body_mesh.visible = false
	_shape.disabled = true
	velocity = Vector3.ZERO
	entered_vehicle.emit(car)


## Gets out beside the driver's door if the car is slow enough and there is ground. Returns success.
func try_exit_vehicle() -> bool:
	if vehicle == null:
		return false
	if vehicle.linear_velocity.length() > config.exit_max_speed_mps:
		return false
	var spot := exit_position(vehicle)
	if spot == Vector3.INF:
		return false
	var car := vehicle
	vehicle = null
	car.driver_peer_id = 0
	global_position = spot
	_body_mesh.visible = true
	_shape.disabled = false
	velocity = Vector3.ZERO
	_yaw = car.global_rotation.y
	_apply_camera_angles()
	exited_vehicle.emit(car)
	return true


## Ground position beside the driver's door (left side, -X in the car's frame), or INF when blocked.
func exit_position(car: Node3D) -> Vector3:
	var side := car.global_position - car.global_basis.x * config.exit_side_offset_m
	var from := side + Vector3.UP * config.exit_probe_up_m
	var to := side - Vector3.UP * config.exit_probe_down_m
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [car.get_rid(), get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"] + Vector3.UP * 0.05
