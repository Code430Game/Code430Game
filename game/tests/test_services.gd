extends GdUnitTestSuite
## add-emergency-services 2.x: places load, the nearest one is found, arrivals are on the street.

const PACK_ID := "code430.ottawa-centretown"


func test_the_pack_has_police_hospitals_and_a_helipad() -> void:
	var places := Services.load_places(PackLocator.find_pack(PACK_ID))
	var kinds := {}
	for p in places:
		kinds[p.kind] = int(kinds.get(p.kind, 0)) + 1
	assert_int(int(kinds.get("police", 0))).is_greater_equal(1)
	assert_int(int(kinds.get("hospital", 0))).is_greater_equal(2)
	assert_int(int(kinds.get("helipad", 0))).is_greater_equal(1)
	var hq := places.filter(func(p: Services.Place) -> bool: return p.name == "Ottawa Police Headquarters")
	assert_int(hq.size()).is_equal(1)


func test_nearest_and_arrival_on_the_street() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack(PACK_ID))).is_true()
	var hq: Services.Place = pack.services.filter(func(p: Services.Place) -> bool: return p.name == "Ottawa Police Headquarters")[0]
	var near := Services.nearest(pack.services, "police", hq.at + Vector3(20, 0, 0))
	assert_str(near.name).is_equal("Ottawa Police Headquarters")
	var at := Services.arrival(hq, pack.graph)
	assert_float(at.distance_to(hq.at)).is_less(150.0)  # on the street outside, not across town
	assert_object(pack.graph.nearest_edge(at, 5.0)).is_not_null()
	assert_object(Services.nearest(pack.services, "volcano", Vector3.ZERO)).is_null()
