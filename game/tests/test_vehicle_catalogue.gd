extends GdUnitTestSuite
## VehicleCatalogue: base set, pack merge, weighted picks by road group and hour, liveries.

const CatalogueScript := preload("res://actors/vehicles/vehicle_catalogue.gd")


func _catalogue() -> Node:
	var c: Node = auto_free(CatalogueScript.new())
	c.load_base()
	return c


func test_base_set_has_the_nine_classes_and_a_fallback() -> void:
	var c := _catalogue()
	assert_int(c.ids().size()).is_equal(9)
	for cls: String in CatalogueScript.BODY_CLASSES:
		var found := false
		for id in c.ids():
			if c.entry(id)["body_class"] == cls:
				found = true
		assert_bool(found).override_failure_message("no %s in the base set" % cls).is_true()
	assert_str(c.default_player).is_equal("sedan")
	assert_str(c.entry("no-such-car")["id"]).is_equal("sedan")
	assert_int(c.index_of("bus")).is_greater_equal(0)
	assert_str(c.id_at(c.index_of("bus"))).is_equal("bus")
	assert_str(c.id_at(99)).is_equal("sedan")


func test_pack_entries_merge_after_the_base_set() -> void:
	var c := _catalogue()
	var limo: Dictionary = c.entry("sedan").duplicate(true)
	limo["id"] = "pack.limo"
	var faster: Dictionary = c.entry("coupe").duplicate(true)
	faster["top_speed_kph"] = 260.0
	var bad: Dictionary = c.entry("sedan").duplicate(true)
	bad["id"] = "pack.hover"
	bad["body_class"] = "hovercraft"
	assert_int(c.merge({"vehicles": [limo, faster, bad]})).is_equal(2)
	assert_bool(c.has("pack.limo")).is_true()
	assert_bool(c.has("pack.hover")).is_false()
	assert_float(float(c.entry("coupe")["top_speed_kph"])).is_equal(260.0)  # same id replaces
	assert_int(c.ids().size()).is_equal(10)
	assert_int(c.index_of("pack.limo")).is_equal(9)  # appended: base indices stay stable


func test_road_groups() -> void:
	assert_str(CatalogueScript.road_group("motorway_link")).is_equal("motorway")
	assert_str(CatalogueScript.road_group("secondary")).is_equal("arterial")
	assert_str(CatalogueScript.road_group("residential")).is_equal("local")


func _mix(c: Node, road_class: String, hour: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var counts := {}
	for i in range(4000):
		var id: String = c.pick_for_spawn(road_class, hour, rng)
		counts[id] = int(counts.get(id, 0)) + 1
	return counts


func test_vans_and_trucks_by_day_taxis_by_night() -> void:
	var c := _catalogue()
	var noon := _mix(c, "primary", 12.0)
	var late := _mix(c, "primary", 22.0)
	var work_noon: int = int(noon.get("van", 0)) + int(noon.get("box_truck", 0))
	var work_late: int = int(late.get("van", 0)) + int(late.get("box_truck", 0))
	assert_int(work_noon).is_greater(work_late * 2)
	assert_int(int(late.get("taxi", 0))).is_greater(int(noon.get("taxi", 0)) * 2)
	assert_int(int(noon.get("sedan", 0))).is_greater(int(noon.get("coupe", 0)))


func test_buses_stay_off_local_streets_and_can_be_excluded() -> void:
	var c := _catalogue()
	assert_int(int(_mix(c, "residential", 12.0).get("bus", 0))).is_equal(0)
	var rng := RandomNumberGenerator.new()
	for i in range(500):
		assert_str(c.pick_for_spawn("primary", 12.0, rng, true)).is_not_equal("bus")


func test_taxi_livery_and_colours() -> void:
	var c := _catalogue()
	var livery: Dictionary = c.livery("taxi")
	assert_str(str(livery.get("roof_sign", ""))).is_equal("TAXI")
	assert_dict(c.livery("sedan")).is_empty()
	var rng := RandomNumberGenerator.new()
	var col: Color = c.pick_color("taxi", rng)
	assert_float(col.r).is_greater(0.9)  # taxi yellow
