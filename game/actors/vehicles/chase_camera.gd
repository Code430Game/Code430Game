class_name ChaseCamera
extends Camera3D
## Follows a target from behind with smoothing. Right stick orbits temporarily. An aircraft
## (add-flyable-helicopter) gives its own distance and height, further back as it speeds up.
## `mode` cycles chase, top-down (follows and turns with the car) and high top-down.
## `look_behind` (held R3) swings the chase view round to face backwards at once, and back on release.

enum Mode { CHASE, TOPDOWN, HIGH }
const TOPDOWN_HEIGHT_M := 45.0
const HIGH_HEIGHT_M := 160.0

@export var target: Node3D
@export var distance_m: float = 7.5
@export var height_m: float = 3.0
@export var look_height_m: float = 1.0
@export var position_smoothing: float = 6.0
@export var orbit_speed_rad_s: float = 2.5
@export var orbit_return_speed: float = 3.0

var _orbit: float = 0.0
const EDGE_PROBE_M := 0.45  # the second ray's height above the first
const CAMERA_CLEARANCE_M := 0.35
var mode: int = Mode.CHASE
## When positive, top-down modes use this height (the testbed's --topdown=<m> for screenshots).
var height_override: float = -1.0
## While true the chase view looks back past the car's nose at what is behind it.
var look_behind: bool = false
var _was_behind: bool = false


## Next camera mode in the cycle.
func cycle_mode() -> void:
	mode = (mode + 1) % 3


## Human-readable mode name for the HUD.
func mode_name() -> String:
	match mode:
		Mode.TOPDOWN:
			return "top-down"
		Mode.HIGH:
			return "high"
	return "chase"


func _process(delta: float) -> void:
	if target == null:
		return
	if mode != Mode.CHASE:
		var h := TOPDOWN_HEIGHT_M if mode == Mode.TOPDOWN else HIGH_HEIGHT_M
		if height_override > 0.0:
			h = height_override
		var desired_top := target.global_position + Vector3(0.0, h, 0.0)
		global_position = global_position.lerp(desired_top, clampf(position_smoothing * delta, 0.0, 1.0))
		# Look straight down with the car's heading up the screen (nudged so look_at has a direction).
		var forward := -target.global_basis.z
		forward.y = 0.0
		if forward.length_squared() < 1e-6:
			forward = Vector3.FORWARD
		look_at(target.global_position, forward.normalized())
		return
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if absf(look.x) > 0.0:
		_orbit += -look.x * orbit_speed_rad_s * delta
	else:
		_orbit = move_toward(_orbit, 0.0, orbit_return_speed * delta)
	var snap := look_behind != _was_behind  # a glance back is a cut, not a slow swing
	_was_behind = look_behind
	var back := target.global_basis.z.rotated(Vector3.UP, PI if look_behind else _orbit)
	back.y = 0.0
	back = back.normalized()
	# Long vehicles (vans, trucks, buses) get pulled back so they stay in frame. An aircraft sets
	# its own distance and height (chase_distance_m, chase_height_m), pulling back with speed.
	var extra := maxf(float(target.get("length_m")) - 4.6, 0.0) if target.get("length_m") != null else 0.0
	var dist := distance_m + extra
	var up := height_m + extra * 0.25
	if target.get("chase_distance_m") != null:
		dist = float(target.get("chase_distance_m"))
		up = float(target.get("chase_height_m"))
	var desired := target.global_position + back * dist + Vector3.UP * up
	var smoothing := float(target.get("chase_smoothing")) if target.get("chase_smoothing") != null else position_smoothing
	global_position = desired if snap else global_position.lerp(desired, clampf(smoothing * delta, 0.0, 1.0))
	var focus := target.global_position + Vector3.UP * look_height_m
	global_position = _clear_of_world(focus, global_position)
	look_at(focus, Vector3.UP)


## Pulls the camera in front of the first solid world surface between the car and it (a garage
## ceiling, a bridge deck, a wall): from above a ceiling it saw straight through (#43). Cars,
## people and other moving bodies are looked past. A second ray, EDGE_PROBE_M higher, catches
## a ceiling edge the centre ray slips past (an opening over a ramp), which left the camera
## half above the ceiling, seeing both sides (#59).
func _clear_of_world(focus: Vector3, wanted: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return wanted
	var length := focus.distance_to(wanted)
	if length < 0.001:
		return wanted
	var best := length
	for lift in [0.0, EDGE_PROBE_M]:
		var up := Vector3.UP * float(lift)
		best = minf(best, _static_hit_distance(space, focus + up, wanted + up))
	if best >= length:
		return wanted
	return focus + (wanted - focus) / length * maxf(best - CAMERA_CLEARANCE_M, 0.0)


## Distance from `from` toward `to` to the first static body, or INF.
func _static_hit_distance(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> float:
	var exclude: Array[RID] = []
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	for i in range(4):
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return INF
		if hit["collider"] is StaticBody3D:
			return from.distance_to(hit["position"])
		exclude.append(hit["rid"])
	return INF
