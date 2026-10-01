extends GdUnitTestSuite
## The generated car body: three surfaces, sane bounds, white body vertices, wheels optional.


func test_mesh_has_body_dark_and_light_surfaces_within_bounds() -> void:
	var mesh := CarMesh.build(true)
	assert_int(mesh.get_surface_count()).is_equal(3)
	var aabb := mesh.get_aabb()
	assert_float(aabb.size.x).is_equal_approx(CarMesh.WIDTH_M, 0.05)
	assert_float(aabb.size.z).is_equal_approx(CarMesh.LENGTH_M + 0.01, 0.05)
	assert_float(aabb.size.y).is_between(1.2, 1.5)
	assert_float(aabb.position.y).is_greater_equal(-CarMesh.WHEEL_RADIUS_M - 0.01)  # wheels hang below the chassis origin
	for s in range(3):
		assert_int(mesh.surface_get_array_len(s)).is_greater(0)
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for c in colors:
		assert_object(c).is_equal(Color.WHITE)


func test_wheels_only_when_asked() -> void:
	var with_wheels := CarMesh.build(true)
	var without := CarMesh.build(false)
	assert_int(with_wheels.surface_get_array_len(1)).is_greater(without.surface_get_array_len(1))
	assert_int(with_wheels.surface_get_array_len(0)).is_equal(without.surface_get_array_len(0))
