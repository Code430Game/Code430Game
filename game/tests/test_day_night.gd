extends GdUnitTestSuite
## Sun elevation and the night factor by hour, and the clock text.


func test_sun_peaks_at_noon_and_is_under_the_horizon_at_midnight() -> void:
	assert_float(DayNight.elevation_deg(12.0, 62.0)).is_equal_approx(62.0, 0.01)
	assert_float(DayNight.elevation_deg(0.0, 62.0)).is_equal_approx(-62.0, 0.01)
	assert_float(DayNight.elevation_deg(6.0, 62.0)).is_equal_approx(0.0, 0.01)
	assert_float(DayNight.elevation_deg(18.0, 62.0)).is_equal_approx(0.0, 0.01)
	assert_float(DayNight.elevation_deg(9.0, 62.0)).is_between(40.0, 50.0)


func test_night_factor_is_zero_by_day_and_one_well_after_dusk() -> void:
	assert_float(DayNight.night_for_elevation(30.0, 4.0, 10.0)).is_equal(0.0)
	assert_float(DayNight.night_for_elevation(0.0, 4.0, 10.0)).is_equal(0.0)
	assert_float(DayNight.night_for_elevation(-20.0, 4.0, 10.0)).is_equal(1.0)
	assert_float(DayNight.night_for_elevation(-2.0, 4.0, 10.0)).is_equal_approx(0.5, 1e-6)


func test_clock_runs_and_wraps_and_drives_registered_materials() -> void:
	var dn: DayNight = auto_free(DayNight.new())
	dn.config = {"day_minutes": 1.0, "start_hour": 23.5, "dusk_width_deg": 10.0, "night_lights_from_elevation_deg": 4.0, "sun_max_elevation_deg": 62.0}
	add_child(dn)
	dn.set_process(false)
	var lights := StandardMaterial3D.new()
	dn.register_emissive(lights, 4.0)
	dn.apply()
	assert_str(dn.clock_text()).is_equal("23:30")
	assert_float(dn.night_factor()).is_equal(1.0)
	assert_float(lights.emission_energy_multiplier).is_equal_approx(4.0, 1e-6)
	dn._process(45.0)  # 45 s of a 60 s day: 18 hours later, 17:30
	assert_str(dn.clock_text()).is_equal("17:30")
	assert_float(dn.night_factor()).is_less(0.01)
	assert_float(lights.emission_energy_multiplier).is_less(0.05)


func test_weather_dims_the_sun_drives_the_sky_shader_and_the_fog() -> void:
	var dn: DayNight = auto_free(DayNight.new())
	dn.load_config()
	dn.config["start_hour"] = 12.0
	add_child(dn)
	dn.set_process(false)
	dn.hour = 12.0
	var sun: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	add_child(sun)
	var env := Environment.new()
	env.sky = Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/sky/sky.gdshader")
	env.sky.sky_material = mat
	dn.setup(sun, env)
	dn.apply()
	var clear_energy := sun.light_energy
	assert_float(clear_energy).is_greater(1.0)
	assert_bool(env.fog_enabled).is_false()
	var clear_top: Color = mat.get_shader_parameter("top_color")
	dn.weather_coverage = 0.9
	dn.weather_fog = 0.6
	dn.weather_tint = Color(0.8, 0.84, 0.9)
	dn.apply()
	assert_float(sun.light_energy).is_less(clear_energy * 0.5)
	assert_float(float(mat.get_shader_parameter("cloud_coverage"))).is_equal_approx(0.9, 1e-6)
	assert_float(float(mat.get_shader_parameter("sun_disc"))).is_equal_approx(0.04, 1e-6)
	assert_bool(env.fog_enabled).is_true()
	assert_float(env.fog_density).is_greater(0.005)
	var grey_top: Color = mat.get_shader_parameter("top_color")
	assert_bool(grey_top.is_equal_approx(clear_top)).is_false()
	# The high preset's shadow projector appears once the sky is mostly cloud.
	dn.cloud_shadows = true
	dn.apply()
	assert_object(sun.light_projector).is_not_null()
	dn.weather_coverage = 0.1
	dn.apply()
	assert_object(sun.light_projector).is_null()
