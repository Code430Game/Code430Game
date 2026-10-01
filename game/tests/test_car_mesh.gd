extends GdUnitTestSuite
## The generated car body: three surfaces, sane bounds, white body vertices, wheels optional.


func test_mesh_has_body_dark_and_light_surfaces_within_bounds() -> void:
	var mesh := CarMesh.build(true)
	assert_int(mesh.get_surface_count()).is_equal(4)
	var aabb := mesh.get_aabb()
	assert_float(aabb.size.x).is_equal_approx(CarMesh.WIDTH_M, 0.05)
	assert_float(aabb.size.z).is_equal_approx(CarMesh.LENGTH_M + 0.01, 0.05)
	assert_float(aabb.size.y).is_between(1.2, 1.5)
	assert_float(aabb.position.y).is_greater_equal(-CarMesh.WHEEL_RADIUS_M - 0.01)  # wheels hang below the chassis origin
	for s in range(4):
		assert_int(mesh.surface_get_array_len(s)).is_greater(0)
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for c in colors:
		assert_object(c).is_equal(Color.WHITE)


func test_wheels_only_when_asked() -> void:
	var with_wheels := CarMesh.build(true)
	var without := CarMesh.build(false)
	assert_int(with_wheels.surface_get_array_len(1)).is_greater(without.surface_get_array_len(1))
	assert_int(with_wheels.surface_get_array_len(0)).is_equal(without.surface_get_array_len(0))


func test_every_triangle_faces_outward() -> void:
	# Godot front faces are clockwise seen from outside, so the cross product of each emitted
	# triangle points inward: toward the body's centre line, or toward a wheel's own axle.
	var mesh := CarMesh.build(true)
	var centre := Vector3(0.0, 0.6, 0.0)
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var wrong := 0
		for t in range(0, verts.size(), 3):
			var a := verts[t]
			var b := verts[t + 1]
			var c := verts[t + 2]
			var n := (b - a).cross(c - a)
			var centroid := (a + b + c) / 3.0
			var reference := centre
			var on_wheel := centroid.y < 0.6 and absf(absf(centroid.x) - CarMesh.WHEEL_X_M) <= CarMesh.WHEEL_WIDTH_M
			if on_wheel:
				var wz := CarMesh.WHEEL_Z_M if centroid.z > 0.0 else -CarMesh.WHEEL_Z_M
				reference = Vector3(signf(centroid.x) * CarMesh.WHEEL_X_M, CarMesh.WHEEL_RADIUS_M - 0.14, wz)
			if n.dot(centroid - reference) > 1e-6:
				wrong += 1
		assert_int(wrong).override_failure_message("surface %d has %d triangles facing inward" % [s, wrong]).is_equal(0)
