extends GdUnitTestSuite
## Billboards stay off roads (human, 2026-10-06: "some signs in the middle of roads", in issue
## #78's screenshot and under the 417 by the Museum of Nature): no board on a road ribbon, a
## crossing or cycleway, in a junction, under or beside a deck, on a building or in water. A
## post may stand on a sidewalk.

const PACK_ID := "code430.ottawa-centretown"

var _pack: MapPack
var _obstacles: Billboards.Obstacles


func before() -> void:
	_pack = MapPack.new()
	assert_bool(_pack.load(PackLocator.find_pack(PACK_ID))).is_true()
	_obstacles = Billboards.obstacles_from_pack(_pack)


func _edge(id: String, from: Vector3, to: Vector3, road_class: String, width: float) -> RoadGraph.RoadEdge:
	var e := RoadGraph.RoadEdge.new()
	e.id = id
	e.road_class = road_class
	e.width_m = width
	e.polyline = PackedVector3Array([from, to])
	return e


func _blocked_count(boards: Billboards) -> Dictionary:
	var reasons: Dictionary = {}
	for s: Dictionary in boards.sites:
		var why := Billboards.footprint_blocked(s["transform"], _obstacles)
		if why != "":
			reasons[why] = int(reasons.get(why, 0)) + 1
	return reasons


func test_no_board_in_the_pack_stands_on_a_road_junction_deck_building_or_water() -> void:
	var old: Billboards = auto_free(Billboards.new())
	add_child(old)
	old.setup(_pack.graph.edges.values(), _pack.ads, 430)
	var placed: Billboards = auto_free(Billboards.new())
	add_child(placed)
	placed.setup(_pack.graph.edges.values(), _pack.ads, 430, _obstacles)
	var before := _blocked_count(old)
	print("billboards: without obstacles %d boards, blocked %s; with obstacles %d boards, blocked %s" % [old.count(), before, placed.count(), _blocked_count(placed)])
	assert_dict(_blocked_count(placed)).is_empty()
	assert_int(placed.count()).is_greater(old.count() / 2)  # most sites find a clear spot
	for s: Dictionary in placed.sites:
		var parts := str(s["id"]).split(".")
		var host: RoadGraph.RoadEdge = _pack.graph.edges[".".join(parts.slice(1, parts.size() - 1))]
		assert_bool(host.bridge or host.tunnel).override_failure_message("board %s stands beside a deck or in a tunnel" % s["id"]).is_false()


func test_a_side_street_at_the_site_moves_the_board_off_it() -> void:
	# A primary road along +x and a side street crossing its right-hand verge at 60 m, where
	# the first board would stand.
	var main := _edge("main", Vector3(0, 0, 0), Vector3(400, 0, 0), "primary", 14.0)
	var side := _edge("side", Vector3(60, 0, 0), Vector3(60, 0, 80), "residential", 8.0)
	var o := Billboards.Obstacles.new()
	o.add_ribbon(main.polyline, main.width_m * 0.5)
	o.add_ribbon(side.polyline, side.width_m * 0.5)
	var plain := Billboards.place(main, Billboards.FIRST_AT_M, 400.0, null)
	assert_str(Billboards.footprint_blocked(plain, o)).is_equal("road")
	var t := Billboards.place(main, Billboards.FIRST_AT_M, 400.0, o)
	assert_bool(t != Transform3D()).is_true()
	assert_str(Billboards.footprint_blocked(t, o)).is_equal("")
	assert_float(absf(t.origin.x - 60.0)).is_greater(4.0 + 3.0)  # the side street's half width and the panel's
	# A junction there instead: the site keeps the configured distance from it, or is dropped.
	var j := Billboards.Obstacles.new()
	j.add_ribbon(main.polyline, main.width_m * 0.5)
	j.add_junction(Vector2(60, 0))
	var tj := Billboards.place(main, Billboards.FIRST_AT_M, 400.0, j)
	var clear := float(Billboards.config().get("junction_clear_m", 20.0))
	if tj != Transform3D():
		assert_float(Vector2(tj.origin.x - 60.0, tj.origin.z).length()).is_greater_equal(clear)


func test_a_site_with_no_clear_spot_is_dropped() -> void:
	var main := _edge("main", Vector3(0, 0, 0), Vector3(400, 0, 0), "primary", 14.0)
	var o := Billboards.Obstacles.new()
	o.add_ribbon(main.polyline, main.width_m * 0.5)
	o.add_area(PackedVector2Array([Vector2(0, 5), Vector2(400, 5), Vector2(400, 60), Vector2(0, 60)]))  # buildings all along the right
	var boards: Billboards = auto_free(Billboards.new())
	add_child(boards)
	boards.setup([main], [], 1, o)
	assert_int(boards.count()).is_equal(0)


func test_bridges_carry_no_boards() -> void:
	var deck := _edge("deck", Vector3(0, 8, 0), Vector3(400, 8, 0), "primary", 14.0)
	deck.bridge = true
	var boards: Billboards = auto_free(Billboards.new())
	add_child(boards)
	boards.setup([deck], [], 1)
	assert_int(boards.count()).is_equal(0)


func test_placement_is_deterministic() -> void:
	var one: Billboards = auto_free(Billboards.new())
	add_child(one)
	one.setup(_pack.graph.edges.values(), _pack.ads, 430, _obstacles)
	var two: Billboards = auto_free(Billboards.new())
	add_child(two)
	two.setup(_pack.graph.edges.values(), _pack.ads, 430, Billboards.obstacles_from_pack(_pack))
	assert_int(one.count()).is_equal(two.count())
	for i in range(one.count()):
		assert_str(one.sites[i]["id"]).is_equal(two.sites[i]["id"])
		assert_vector((one.sites[i]["transform"] as Transform3D).origin).is_equal((two.sites[i]["transform"] as Transform3D).origin)
