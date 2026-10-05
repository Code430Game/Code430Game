class_name ChaseCamera
extends Camera3D
## Follows a target from behind with smoothing. Right stick orbits temporarily.
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
	# Long vehicles (vans, trucks, buses) get pulled back so they stay in frame.
	var extra := maxf(float(target.get("length_m")) - 4.6, 0.0) if target.get("length_m") != null else 0.0
	var desired := target.global_position + back * (distance_m + extra) + Vector3.UP * (height_m + extra * 0.25)
	global_position = desired if snap else global_position.lerp(desired, clampf(position_smoothing * delta, 0.0, 1.0))
	look_at(target.global_position + Vector3.UP * look_height_m, Vector3.UP)
