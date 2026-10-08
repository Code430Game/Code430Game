extends GdUnitTestSuite
## The particle box: caps from the preset, rain and snow looks, intensity and wind.


func test_caps_come_from_the_preset_and_the_kind_sets_the_look() -> void:
	var p: Precipitation = auto_free(Precipitation.new())
	p.configure({"rain_particles": 1500, "snow_particles": 600})
	add_child(p)
	assert_str(p.kind).is_equal("rain")
	assert_int(p.amount).is_equal(1500)
	assert_float(p.lifetime).is_equal_approx(Precipitation.RAIN_DROP_M / Precipitation.RAIN_SPEED, 1e-6)
	p.set_kind("snow")
	assert_int(p.amount).is_equal(600)
	assert_float(p.lifetime).is_greater(5.0)  # snow drifts down slowly
	var mat := (p.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	assert_int(mat.billboard_mode).is_equal(BaseMaterial3D.BILLBOARD_ENABLED)


func test_intensity_scales_emission_and_zero_stops_it() -> void:
	var p: Precipitation = auto_free(Precipitation.new())
	add_child(p)
	p.set_intensity(0.5)
	assert_bool(p.emitting).is_true()
	assert_float(p.amount_ratio).is_equal_approx(0.5, 1e-6)
	p.set_intensity(0.0)
	assert_bool(p.emitting).is_false()


func test_wind_slants_the_fall() -> void:
	var p: Precipitation = auto_free(Precipitation.new())
	add_child(p)
	p.set_wind(Vector3(6, 0, 0))
	var pm := p.process_material as ParticleProcessMaterial
	assert_float(pm.direction.x).is_greater(0.3)
	assert_float(pm.direction.y).is_less(0.0)


func test_the_box_follows_the_camera() -> void:
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(100, 70, -50)
	var p: Precipitation = auto_free(Precipitation.new())
	add_child(p)
	p._process(0.016)
	assert_float(p.global_position.y).is_greater(cam.global_position.y + 5.0)
	assert_float(p.global_position.distance_to(cam.global_position)).is_less(30.0)
