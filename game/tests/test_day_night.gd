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
