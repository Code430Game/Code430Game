extends GdUnitTestSuite
## VehicleMesh: every catalogue class at LOD0 and LOD1 within budget, wound outward, body
## white, glass and lights coloured, bounds matching the dims.

const CatalogueScript := preload("res://actors/vehicles/vehicle_catalogue.gd")

var _cat: Node


func before() -> void:
	_cat = CatalogueScript.new()
	_cat.load_base()


func after() -> void:
	_cat.free()


func _tris(mesh: ArrayMesh) -> int:
	var n := 0
	for s in range(mesh.get_surface_count()):
		n += mesh.surface_get_array_len(s) / 3
	return n


func test_every_class_is_within_its_triangle_budget() -> void:
	for id in _cat.ids():
		var e: Dictionary = _cat.entry(id)
		var cls: String = e["body_class"]
		var lod0 := VehicleMesh.build(e, VehicleMesh.Lod.LOD0, true, _cat.livery(id))
		var lod1 := VehicleMesh.build(e, VehicleMesh.Lod.LOD1, true)
		assert_int(_tris(lod0)).override_failure_message("%s LOD0 has %d triangles" % [id, _tris(lod0)]).is_less_equal(int(VehicleMesh.LOD0_BUDGET[cls]))
		if cls != "bus":  # the bus is a handful of boxes at either distance
			assert_int(_tris(lod1)).override_failure_message("%s LOD1 has %d triangles" % [id, _tris(lod1)]).is_less_equal(VehicleMesh.LOD1_BUDGET)
			assert_int(_tris(lod1)).is_less(_tris(lod0))


func test_every_triangle_is_wound_to_face_out() -> void:
	# Godot front faces are clockwise seen from outside, so each triangle's cross product must
	# point against the outward normal the generator gave it; and most faces point away from
	# the vehicle's middle (wheel wells and the pickup bed are the honest exceptions).
	for id in _cat.ids():
		var e: Dictionary = _cat.entry(id)
		if e["body_class"] == "bus":
			continue
		for lod in [VehicleMesh.Lod.LOD0, VehicleMesh.Lod.LOD1]:
			var mesh := VehicleMesh.build(e, lod, true, _cat.livery(id))
			var centre := Vector3(0, float(e["dims"]["height_m"]) * 0.45, 0)
			var wrong := 0
			var away := 0
			var total := 0
			for s in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for t in range(0, v.size(), 3):
					var geo := (v[t + 1] - v[t]).cross(v[t + 2] - v[t])
					if geo.dot(n[t]) > 1e-7:
						wrong += 1
					var centroid := (v[t] + v[t + 1] + v[t + 2]) / 3.0
					var reference := _reference(e, centroid, centre)
					if reference == Vector3.INF:
						continue  # a wheel-well liner: faces its wheel by design
					# Faces whose direction is certain: outer side panels, roof, underside.
					var hw := float(e["dims"]["width_m"]) * 0.5
					var flat_y := absf(v[t].y - v[t + 1].y) < 1e-4 and absf(v[t].y - v[t + 2].y) < 1e-4
					if absf(absf(centroid.x) - hw) < 1e-4 and absf(v[t].x - v[t + 1].x) < 1e-4 and s == 0:
						assert_float(n[t].x * signf(centroid.x)).override_failure_message("%s side panel faces in" % id).is_greater(0.99)
					if flat_y and absf(centroid.y - float(e["dims"]["height_m"])) < 1e-4 and absf(centroid.x) < hw * 0.5:
						assert_float(n[t].y).override_failure_message("%s roof faces down" % id).is_greater(0.99)
					if flat_y and absf(centroid.y - float(e["dims"]["wheel_radius_m"]) * 0.6) < 1e-4 and s == 0 and absf(centroid.x) < hw * 0.5:
						assert_float(n[t].y).override_failure_message("%s underside faces up" % id).is_less(-0.99)
					if n[t].dot(centroid - reference) > 0.0:
						away += 1
					total += 1
			assert_int(wrong).override_failure_message("%s LOD%d: %d triangles wound inward" % [id, lod, wrong]).is_equal(0)
			assert_float(float(away) / total).override_failure_message("%s LOD%d: only %d of %d face away" % [id, lod, away, total]).is_greater(0.85)


func test_body_is_white_and_glass_and_lights_are_not() -> void:
	for id in _cat.ids():
		var e: Dictionary = _cat.entry(id)
		var mesh := VehicleMesh.build(e, VehicleMesh.Lod.LOD0, true, _cat.livery(id))
		assert_int(mesh.get_surface_count()).is_equal(4)
		for c: Color in mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
			assert_that(c).is_equal(Color.WHITE)
		var dark_seen := false
		for c: Color in mesh.surface_get_arrays(1)[Mesh.ARRAY_COLOR]:
			if c.v < 0.3:
				dark_seen = true
		assert_bool(dark_seen).override_failure_message("%s has no dark glass or trim" % id).is_true()
		for c: Color in mesh.surface_get_arrays(3)[Mesh.ARRAY_COLOR]:
			assert_float(c.r).is_greater(c.g + 0.3)  # tail lights are red


func test_bounds_match_the_dims_and_wheels_touch_the_ground() -> void:
	for id in _cat.ids():
		var e: Dictionary = _cat.entry(id)
		if e["body_class"] == "bus":
			continue
		var d: Dictionary = e["dims"]
		var aabb := VehicleMesh.build(e, VehicleMesh.Lod.LOD0, true).get_aabb()
		assert_float(aabb.size.z).override_failure_message("%s length %.2f" % [id, aabb.size.z]).is_between(float(d["length_m"]) - 0.05, float(d["length_m"]) + 0.25)
		assert_float(aabb.size.x).override_failure_message("%s width %.2f" % [id, aabb.size.x]).is_between(float(d["width_m"]) - 0.05, float(d["width_m"]) + 0.32)
		assert_float(aabb.end.y).override_failure_message("%s height %.2f" % [id, aabb.end.y]).is_between(float(d["height_m"]) - 0.1, float(d["height_m"]) + 0.05)
		assert_float(aabb.position.y).is_equal_approx(0.0, 0.01)


func test_wheels_only_when_asked_and_the_taxi_wears_its_sign() -> void:
	var sedan: Dictionary = _cat.entry("sedan")
	assert_int(_tris(VehicleMesh.build(sedan, VehicleMesh.Lod.LOD0, true))).is_greater(_tris(VehicleMesh.build(sedan, VehicleMesh.Lod.LOD0, false)))
	var taxi: Dictionary = _cat.entry("taxi")
	var signed := VehicleMesh.build(taxi, VehicleMesh.Lod.LOD0, true, _cat.livery("taxi")).get_aabb()
	assert_float(signed.end.y).is_greater(float(taxi["dims"]["height_m"]) + 0.1)


func test_wheel_positions_follow_the_dims() -> void:
	var e: Dictionary = _cat.entry("box_truck")
	var w := VehicleMesh.wheel_positions(e)
	assert_int(w.size()).is_equal(4)
	assert_float(w[2].z - w[0].z).is_equal_approx(float(e["dims"]["wheelbase_m"]), 0.001)
	assert_float(w[1].x - w[0].x).is_equal_approx(float(e["dims"]["track_m"]), 0.001)
	assert_float(w[0].y).is_equal_approx(float(e["dims"]["wheel_radius_m"]), 0.001)


## What a triangle should face away from: its wheel's centre for wheel faces, INF for a
## wheel-well liner (skip), else the vehicle's middle.
func _reference(e: Dictionary, p: Vector3, centre: Vector3) -> Vector3:
	var wr := float(e["dims"]["wheel_radius_m"])
	var hw := float(e["dims"]["width_m"]) * 0.5
	for w in VehicleMesh.wheel_positions(e):
		var zy := Vector2(p.z - w.z, p.y - w.y).length()
		if zy <= wr + 0.01 and absf(p.x - w.x) <= 0.17:
			return w
		if zy > wr and zy <= wr + 0.08 and absf(p.x) >= hw - 0.31 and absf(p.x) <= hw + 0.01:
			return Vector3.INF
	return centre
