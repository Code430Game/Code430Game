class_name DayNight
extends Node
## Time of day: moves the sun, blends the sky and ambient light, and drives everything
## that glows at night through a single night factor.
##
## Approach: the hour runs 0..24 over `day_minutes` real minutes. Sun elevation is a sine
## of the hour (max at noon), azimuth sweeps east to west. The night factor is 0 by day and
## 1 once the sun is a few degrees under the horizon; the sky blends day, dusk and night sets
## around sunrise and sunset. Registered emissive materials scale their emission by the
## factor; registered shader materials get a `night` uniform.

const CONFIG_PATH := "res://world/sky/day_night.json"

var config: Dictionary = {}
var hour: float = 14.0
var running: bool = true
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment
var sky_material: ProceduralSkyMaterial
var sky_shader: ShaderMaterial  # sky.gdshader: the gradient plus clouds (add-weather)
## Weather inputs, written by WeatherController each frame (0 and white when there is none):
## cloud coverage dims the sun and ambient, fog drives the distance fog and hides the sun disc,
## the tint colours the clouds, wind times time scrolls them.
var weather_coverage: float = 0.0
var weather_fog: float = 0.0
var weather_tint: Color = Color.WHITE
var weather_wind: Vector2 = Vector2.ZERO
var weather_time: float = 0.0
var cloud_layers: int = 1
var cloud_shadows: bool = false
var _base_volumetric_density: float = 0.0
var _emissive: Array = []  # [[StandardMaterial3D, base energy], ...]
var _shaders: Array[ShaderMaterial] = []
var _night_factor: float = 0.0


func _ready() -> void:
	if config.is_empty():
		load_config()
	hour = float(config.get("start_hour", 14.0))


func load_config(path: String = CONFIG_PATH) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DayNight: cannot read %s" % path)
		return false
	config = parsed
	return true


## Wires the lights and environment this node drives. Creates the moon light itself.
func setup(sun_light: DirectionalLight3D, env: Environment) -> void:
	sun = sun_light
	environment = env
	if env != null and env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		sky_material = env.sky.sky_material
	elif env != null and env.sky != null and env.sky.sky_material is ShaderMaterial:
		sky_shader = env.sky.sky_material
		sky_shader.set_shader_parameter("cloud_noise", WeatherController.cloud_noise_texture())
	if env != null:
		_base_volumetric_density = env.volumetric_fog_density
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	add_child(moon)
	apply()


## A material whose emission should follow the night factor (base energy = its daytime value).
func register_emissive(mat: StandardMaterial3D, night_energy: float) -> void:
	_emissive.append([mat, night_energy])


## A ShaderMaterial with a `night` uniform.
func register_shader(mat: ShaderMaterial) -> void:
	_shaders.append(mat)


func night_factor() -> float:
	return _night_factor


## Sets the clock to `h` and stops it there (the Testing tab, add-world-menu).
func fix_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	running = false
	apply()


## Starts the clock again from the current hour.
func run() -> void:
	running = true


## Real minutes a game day takes.
func day_minutes() -> float:
	return float(config.get("day_minutes", 24.0))


func set_day_minutes(minutes: float) -> void:
	config["day_minutes"] = maxf(minutes, 1.0)


## Clock text for the HUD.
func clock_text() -> String:
	var h := int(floor(hour)) % 24
	var m := int(floor(fmod(hour, 1.0) * 60.0))
	return "%02d:%02d" % [h, m]


func _process(delta: float) -> void:
	if running:
		var day_minutes := float(config.get("day_minutes", 24.0))
		hour = fmod(hour + delta / (day_minutes * 60.0) * 24.0, 24.0)
	apply()


## Sun elevation in degrees for an hour: peaks at noon, negative at night.
static func elevation_deg(h: float, max_elevation_deg: float) -> float:
	return sin((h - 6.0) / 24.0 * TAU) * max_elevation_deg


## 0 while the sun is up, rising to 1 once it is `lights_from_deg` under the horizon.
static func night_for_elevation(elev_deg: float, lights_from_deg: float, _dusk_width_deg: float) -> float:
	return clampf(-elev_deg / maxf(lights_from_deg, 0.1), 0.0, 1.0)


## Applies the current hour to the sun, moon, sky, ambient and registered materials.
func apply() -> void:
	var elev := elevation_deg(hour, float(config.get("sun_max_elevation_deg", 62.0)))
	var azimuth := (hour - 12.0) / 24.0 * TAU  # 0 at noon (south), sweeping west
	var dusk_w := float(config.get("dusk_width_deg", 10.0))
	_night_factor = night_for_elevation(elev, float(config.get("night_lights_from_elevation_deg", 4.0)), dusk_w)
	var daylight := clampf(elev / dusk_w, 0.0, 1.0)  # 0 at the horizon, 1 well above it
	if sun != null:
		# Sun direction: elevation above the horizon, azimuth around the up axis; south is +z.
		var dir := Vector3(sin(azimuth) * cos(deg_to_rad(elev)), -sin(deg_to_rad(elev)), cos(azimuth) * cos(deg_to_rad(elev)))
		if dir.length_squared() > 1e-9:
			sun.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(0, 200, 0))
		var warm := _c(config.get("sun_color_horizon", [1, 0.62, 0.38]))
		var noon := _c(config.get("sun_color_noon", [1, 0.98, 0.94]))
		sun.light_color = warm.lerp(noon, daylight).lerp(weather_tint * warm.lerp(noon, daylight), weather_coverage)
		# Overcast dims the sun; fog flattens it further. The sky shader hides the disc itself.
		sun.light_energy = float(config.get("sun_energy_noon", 1.3)) * daylight * (1.0 - weather_coverage * 0.6) * (1.0 - weather_fog * 0.5)
		sun.visible = elev > -0.5
		if cloud_shadows:
			# A noise projector on the sun stands in for cloud shadows once the sky is mostly cloud.
			var want: Texture2D = WeatherController.cloud_noise_texture() if weather_coverage > 0.45 else null
			if sun.light_projector != want:
				sun.light_projector = want
		elif sun.light_projector != null:
			sun.light_projector = null
	if moon != null:
		moon.light_color = _c(config.get("moon_color", [0.55, 0.65, 0.9]))
		moon.light_energy = float(config.get("moon_energy", 0.12)) * _night_factor
		moon.visible = _night_factor > 0.01
		moon.global_transform = Transform3D(Basis.looking_at(Vector3(0.3, -0.8, -0.5).normalized(), Vector3.UP), Vector3(0, 200, 0))
	if sky_material != null or sky_shader != null:
		var day: Dictionary = config.get("sky_day", {})
		var dusk: Dictionary = config.get("sky_dusk", {})
		var night: Dictionary = config.get("sky_night", {})
		# Day above the dusk band, dusk around the horizon, night below it.
		var t_dusk := clampf(1.0 - absf(elev) / dusk_w, 0.0, 1.0)
		var top := _c(day.get("top")) if elev > 0.0 else _c(night.get("top"))
		var hor := _c(day.get("horizon")) if elev > 0.0 else _c(night.get("horizon"))
		var sky_top := top.lerp(_c(dusk.get("top")), t_dusk)
		var sky_hor := hor.lerp(_c(dusk.get("horizon")), t_dusk)
		# Weather: overcast greys the sky toward the tinted horizon, fog pulls everything to one tone.
		var grey := sky_hor.lerp(sky_top, 0.35) * weather_tint
		sky_top = sky_top.lerp(grey, weather_coverage * 0.7).lerp(sky_hor * weather_tint, weather_fog)
		sky_hor = sky_hor.lerp(sky_hor * weather_tint, maxf(weather_coverage * 0.5, weather_fog))
		if sky_material != null:
			sky_material.sky_top_color = sky_top
			sky_material.sky_horizon_color = sky_hor
			sky_material.ground_horizon_color = sky_material.sky_horizon_color
		if sky_shader != null:
			sky_shader.set_shader_parameter("top_color", sky_top)
			sky_shader.set_shader_parameter("horizon_color", sky_hor)
			sky_shader.set_shader_parameter("night", _night_factor)
			sky_shader.set_shader_parameter("cloud_coverage", weather_coverage)
			sky_shader.set_shader_parameter("cloud_tint", weather_tint)
			sky_shader.set_shader_parameter("cloud_layers", cloud_layers)
			sky_shader.set_shader_parameter("cloud_offset", weather_wind * weather_time * 0.0004)
			sky_shader.set_shader_parameter("sun_disc", clampf(1.0 - weather_fog * 1.6, 0.0, 1.0))
	if environment != null:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_sky_contribution = 1.0
		environment.ambient_light_energy = lerpf(float(config.get("ambient_day", 0.5)), float(config.get("ambient_night", 0.18)), _night_factor) * (1.0 - weather_coverage * 0.25)
		# Distance fog follows the weather's fog value; the preset's volumetric haze thickens with it.
		environment.fog_enabled = weather_fog > 0.001
		environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		environment.fog_density = weather_fog * weather_fog * float(config.get("fog_density_max", 0.03))
		environment.fog_light_color = (sky_material.sky_horizon_color if sky_material != null else Color(0.7, 0.72, 0.76)).lerp(Color(0.05, 0.06, 0.09), _night_factor)
		environment.fog_sky_affect = clampf(weather_fog * 1.2, 0.0, 1.0)
		if environment.volumetric_fog_enabled:
			environment.volumetric_fog_density = _base_volumetric_density + weather_fog * float(config.get("volumetric_fog_max", 0.02))
	for pair in _emissive:
		var mat: StandardMaterial3D = pair[0]
		mat.emission_energy_multiplier = float(pair[1]) * _night_factor
	for sm in _shaders:
		sm.set_shader_parameter("night", _night_factor)


static func _c(v: Variant) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return Color.WHITE
