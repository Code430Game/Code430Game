extends GdUnitTestSuite
## KitVehicle: the kit models load into VehicleMesh's four surfaces at LOD0, within budget,
## with wheels only when asked, matching the catalogue dims the build tool measured.

const CatalogueScript := preload("res://actors/vehicles/vehicle_catalogue.gd")
const KIT_LOD0_BUDGET := 2600  # the kit bodies are 1,300-1,900 triangles, wheels about 120 each

var _cat: Node


func before() -> void:
	_cat = CatalogueScript.new()
	_cat.load_base()


func after() -> void:
	_cat.free()


func _kit_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _cat.ids():
		if KitVehicle.has_model(_cat.entry(id)):
			out.append(id)
	return out


func _aabb(mesh: ArrayMesh, surfaces: Array) -> AABB:
	var box := AABB()
	var first := true
	for s: int in surfaces:
		for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			if first:
				box = AABB(v, Vector3.ZERO)
				first = false
			else:
				box = box.expand(v)
	return box


func test_the_everyday_and_service_vehicles_have_kit_models() -> void:
	var ids := _kit_ids()
	for id in ["sedan", "hatchback", "coupe", "suv", "pickup", "van", "box_truck", "taxi", "police", "ambulance"]:
		assert_bool(ids.has(id)).override_failure_message("%s has no kit model" % id).is_true()


func test_lod0_is_the_kit_model_and_lod1_stays_parametric() -> void:
	for id in _kit_ids():
		var e: Dictionary = _cat.entry(id)
		var lod0 := VehicleMesh.build(e, VehicleMesh.Lod.LOD0)
		var lod1 := VehicleMesh.build(e, VehicleMesh.Lod.LOD1)
		assert_object(lod0).is_same(KitVehicle.build(e))
		assert_int(lod0.get_surface_count()).is_equal(4)
		assert_int(KitVehicle.triangles(lod0)).override_failure_message("%s has %d triangles" % [id, KitVehicle.triangles(lod0)]).is_less_equal(KIT_LOD0_BUDGET)
		assert_int(KitVehicle.triangles(lod1)).is_less(KitVehicle.triangles(lod0))


func test_every_surface_has_geometry_and_the_body_is_white() -> void:
	for id in _kit_ids():
		var mesh := KitVehicle.build(_cat.entry(id))
		for s in range(4):
			assert_int(mesh.surface_get_array_len(s)).override_failure_message("%s surface %d is empty" % [id, s]).is_greater(0)
		var whites := 0
		var colours: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		for c in colours:
			if c.is_equal_approx(Color.WHITE):
				whites += 1
		assert_float(float(whites) / colours.size()).override_failure_message("%s body is not mostly white" % id).is_greater(0.6)


func test_wheels_only_when_asked() -> void:
	for id in _kit_ids():
		var e: Dictionary = _cat.entry(id)
		var with := KitVehicle.triangles(KitVehicle.build(e, true))
		var without := KitVehicle.triangles(KitVehicle.build(e, false))
		assert_int(with - without).override_failure_message("%s wheels add %d triangles" % [id, with - without]).is_between(200, 800)


func test_the_model_matches_the_catalogue_dims() -> void:
	# The build tool measured the dims from the model: the bounds, the ground and the wheel
	# layout must still agree, or the physics box and the wheel nodes drift off the body.
	for id in _kit_ids():
		var e: Dictionary = _cat.entry(id)
		var d: Dictionary = e["dims"]
		var mesh := KitVehicle.build(e, true)
		var box := _aabb(mesh, [0, 1, 2, 3])
		assert_float(box.size.z).override_failure_message("%s length" % id).is_equal_approx(float(d["length_m"]), 0.02)
		assert_float(box.size.y).override_failure_message("%s height" % id).is_equal_approx(float(d["height_m"]), 0.02)
		assert_float(box.position.y).override_failure_message("%s wheels on the ground" % id).is_equal_approx(0.0, 0.02)
		assert_float(box.get_center().z).override_failure_message("%s centred" % id).is_equal_approx(0.0, 0.02)
		var front := _aabb(mesh, [0, 1, 2, 3]).position.z
		var wheels := VehicleMesh.wheel_positions(e)
		assert_float(wheels[0].z - front).override_failure_message("%s front overhang" % id).is_equal_approx(float(d["front_overhang_m"]), 0.02)
		assert_float(wheels[0].x).override_failure_message("%s front left wheel is on the left (-x)" % id).is_less(0.0)


func test_headlights_are_at_the_front_and_tail_lights_at_the_back() -> void:
	for id in _kit_ids():
		var mesh := KitVehicle.build(_cat.entry(id))
		assert_float(_aabb(mesh, [2]).get_center().z).override_failure_message("%s headlights" % id).is_less(0.0)
		assert_float(_aabb(mesh, [3]).get_center().z).override_failure_message("%s tail lights" % id).is_greater(0.0)
