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


## Human, 2026-10-06: the board moved off the road under the 417 near (765, 910) clipped a
## tree. Checked here against the pack's own tree rows, not the placement's index: no panel
## overlaps a crown at its height, and no post stands on a trunk.
func test_no_board_in_the_pack_clips_a_tree() -> void:
	var no_trees := Billboards.obstacles_from_pack(_pack)
	no_trees.trees = {}
	var without: Billboards = auto_free(Billboards.new())
	add_child(without)
	without.setup(_pack.graph.edges.values(), _pack.ads, 430, no_trees)
	var placed: Billboards = auto_free(Billboards.new())
	add_child(placed)
	placed.setup(_pack.graph.edges.values(), _pack.ads, 430, _obstacles)
	var cfg := Billboards.config()
	var mid := float(cfg.get("crown_mid", 0.62))
	var half := float(cfg.get("crown_half_height", 0.28))
	var rows: Array = []
	for coord: Vector2i in _pack.vegetation_chunks:
		rows.append_array((_pack.vegetation_chunks[coord] as Dictionary).get("trees", []))
	var clips := [_clips(without, rows, mid, half), _clips(placed, rows, mid, half)]
	var moved := 0
	var by_id: Dictionary = {}
	for s: Dictionary in without.sites:
		by_id[s["id"]] = (s["transform"] as Transform3D).origin
	for s: Dictionary in placed.sites:
		if by_id.has(s["id"]) and (by_id[s["id"]] as Vector3).distance_to((s["transform"] as Transform3D).origin) > 0.01:
			moved += 1
	print("billboards: trees ignored %d boards, %d clip a tree; trees as obstacles %d boards (%d moved, %d dropped), %d clip" % [without.count(), clips[0], placed.count(), moved, without.count() - placed.count(), clips[1]])
	assert_int(clips[1]).is_equal(0)
	assert_int(placed.count()).is_greater(without.count() * 3 / 4)  # most boards still stand


## Boards whose panel (POST_H_M to POST_H_M + PANEL_H_M up, PANEL_W_M across) passes through a
## tree crown modelled as CanopyCover does, or whose post stands within a trunk.
func _clips(boards: Billboards, rows: Array, mid: float, half: float) -> int:
	var n := 0
	for s: Dictionary in boards.sites:
		var t: Transform3D = s["transform"]
		var across := t.basis.x * (Billboards.PANEL_W_M * 0.5)
		var a := Vector2((t.origin + across).x, (t.origin + across).z)
		var b := Vector2((t.origin - across).x, (t.origin - across).z)
		var post := Vector2(t.origin.x, t.origin.z)
		var low := t.origin.y + Billboards.POST_H_M
		var high := low + Billboards.PANEL_H_M
		for row: Array in rows:
			var at := Vector2(float(row[0]), float(row[2]))
			if at.distance_to(post) > 20.0:
				continue
			var h := float(row[4])
			var base := float(row[1])
			var hit := at.distance_to(post) < VegetationBuilder.TRUNK_HALF_M
			if not hit and base + h * (mid + half) >= low and base + h * (mid - half) <= high:
				hit = Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) < float(row[5])
			if hit:
				n += 1
				break
	return n


func test_a_tree_at_the_site_moves_the_board() -> void:
	var main := _edge("main", Vector3(0, 0, 0), Vector3(400, 0, 0), "primary", 14.0)
	var o := Billboards.Obstacles.new()
	o.add_ribbon(main.polyline, main.width_m * 0.5)
	var plain := Billboards.place(main, Billboards.FIRST_AT_M, 400.0, o)
	assert_str(Billboards.footprint_blocked(plain, o)).is_equal("")
	# A 10 m broadleaf with a 3 m crown right where the first board's panel stands.
	var cfg := Billboards.config()
	o.add_tree([plain.origin.x + 1.0, 0.0, plain.origin.z, "broadleaf", 10.0, 3.0, 1, "row"], float(cfg.get("crown_mid", 0.62)), float(cfg.get("crown_half_height", 0.28)))
	assert_str(Billboards.footprint_blocked(plain, o)).is_equal("tree")
	var t := Billboards.place(main, Billboards.FIRST_AT_M, 400.0, o)
	assert_bool(t != Transform3D()).is_true()
	assert_str(Billboards.footprint_blocked(t, o)).is_equal("")
	assert_float(t.origin.distance_to(plain.origin)).is_greater(1.0)
	# A short tree whose crown stays below the panel does not move it.
	var low := Billboards.Obstacles.new()
	low.add_ribbon(main.polyline, main.width_m * 0.5)
	low.add_tree([plain.origin.x + 2.0, 0.0, plain.origin.z, "bush_round", 2.5, 1.5, 2, "scatter"], float(cfg.get("crown_mid", 0.62)), float(cfg.get("crown_half_height", 0.28)))
	assert_str(Billboards.footprint_blocked(plain, low)).is_equal("")
