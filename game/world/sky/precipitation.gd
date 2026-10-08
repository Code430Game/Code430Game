class_name Precipitation
extends GPUParticles3D
## Rain or snow around the camera: one particle box that follows the active camera, emitting
## downward with the wind. Rain is a stretched streak, snow a soft drifting dot. Nothing lands.
##
## Approach: the box sits above and a little ahead of the camera and the particles live just
## long enough to fall past it, so the view is full and nothing is drawn far below the player.
## `set_intensity` scales emission (0 stops it), `set_kind` rebuilds the look for rain or snow;
## the counts per preset come from presets.json (rain_particles, snow_particles).

const RAIN_SPEED := 10.0
const SNOW_SPEED := 1.6
const BOX_HALF_M := 14.0
const RAIN_DROP_M := 18.0  # how far a drop falls before it dies (box top to below the camera)
const SNOW_DROP_M := 14.0
const AHEAD_M := 4.0

var kind: String = ""
var rain_amount: int = 1500
var snow_amount: int = 600
var wind: Vector3 = Vector3.ZERO
var _intensity: float = 0.0


func _ready() -> void:
	visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	emitting = false
	if kind == "":
		set_kind("rain")


## Reads the particle caps from a graphics preset.
func configure(preset: Dictionary) -> void:
	rain_amount = int(preset.get("rain_particles", 1500))
	snow_amount = int(preset.get("snow_particles", 600))
	if kind != "":
		set_kind(kind)


## Rebuilds the emitter for "rain" or "snow".
func set_kind(new_kind: String) -> void:
	kind = new_kind
	var snow := kind == "snow"
	var speed := SNOW_SPEED if snow else RAIN_SPEED
	var drop := SNOW_DROP_M if snow else RAIN_DROP_M
	amount = snow_amount if snow else rain_amount
	lifetime = drop / speed
	explosiveness = 0.0
	randomness = 0.3 if snow else 0.1
	fixed_fps = 0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(BOX_HALF_M, 0.5, BOX_HALF_M)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 12.0 if snow else 2.0
	pm.initial_velocity_min = speed * 0.8
	pm.initial_velocity_max = speed * 1.1
	pm.gravity = Vector3.ZERO  # constant fall: the box height and lifetime are matched
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	if snow:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_noise_scale = 4.0
	process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09) if snow else Vector2(0.018, 0.42)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if snow else BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.albedo_color = Color(0.95, 0.96, 1.0, 0.85) if snow else Color(0.75, 0.8, 0.9, 0.38)
	mat.no_depth_test = false
	quad.material = mat
	draw_pass_1 = quad
	_apply_wind()
	set_intensity(_intensity)


## Emission as a fraction of the preset cap; 0 switches the emitter off.
func set_intensity(amount01: float) -> void:
	_intensity = clampf(amount01, 0.0, 1.0)
	amount_ratio = maxf(_intensity, 0.01)
	emitting = _intensity > 0.001


## Wind in m/s, added to every particle's velocity so rain slants and snow drifts.
func set_wind(w: Vector3) -> void:
	wind = w
	_apply_wind()


func _apply_wind() -> void:
	var pm := process_material as ParticleProcessMaterial
	if pm == null:
		return
	var speed := SNOW_SPEED if kind == "snow" else RAIN_SPEED
	var v := Vector3(wind.x, -speed, wind.z)
	pm.direction = v.normalized()
	pm.initial_velocity_min = v.length() * 0.8
	pm.initial_velocity_max = v.length() * 1.1


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 1e-6:
		forward = forward.normalized()
	var drop := SNOW_DROP_M if kind == "snow" else RAIN_DROP_M
	global_position = cam.global_position + forward * AHEAD_M + Vector3(0, drop - 4.0, 0)
