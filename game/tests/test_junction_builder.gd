extends GdUnitTestSuite
## Junction polygons on a synthetic four-way cross.

const WIDTH := 8.0


func _cross_graph() -> RoadGraph:
	var edges := []
	var arms := [["e", [[0, 0, 0], [100, 0, 0]], "n_e"], ["w", [[0, 0, 0], [-100, 0, 0]], "n_w"], ["n", [[0, 0, 0], [0, 0, -100]], "n_n"], ["s", [[0, 0, 0], [0, 0, 100]], "n_s"]]
	var nodes := [{"id": "n_c", "position": [0, 0, 0], "ground_y": 0, "junction_type": "junction"}]
	for arm in arms:
		nodes.append({"id": arm[2], "position": arm[1][1], "ground_y": 0, "junction_type": "dead_end"})
		edges.append({
			"id": "w%s.0" % arm[0], "from": "n_c", "to": arm[2], "polyline": arm[1], "class": "residential",
			"lanes_forward": 1, "lanes_backward": 1, "oneway": false, "speed_kph": 40, "width_m": WIDTH,
			"layer": 0, "bridge": false, "tunnel": false, "name": arm[0], "osm_way_id": 1, "defaulted_fields": [],
			"access": null, "length_m": 100.0,
		})
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})


func test_four_way_cross_polygon() -> void:
	var graph := _cross_graph()
	var junctions := JunctionBuilder.build_all(graph)
	assert_int(junctions.size()).is_equal(1)
	var j: JunctionBuilder.Junction = junctions["n_c"]
	assert_bool(j.fallback_hull).is_false()
	assert_int(j.polygon_xz.size()).is_equal(4 * (2 + JunctionBuilder.FILLET_STEPS))
	for eid in ["we.0", "ww.0", "wn.0", "ws.0"]:
		assert_float(j.trims[eid]).is_equal_approx(WIDTH * 0.5 + JunctionBuilder.TRIM_MARGIN_M, 1e-4)
	assert_int(Geometry2D.triangulate_polygon(j.polygon_xz).size()).is_greater(0)
	# The sharp corners at (+-4, +-4) are replaced by curves, so no vertex sits on them.
	for p in j.polygon_xz:
		var on_corner := absf(absf(p.x) - WIDTH * 0.5) < 1e-3 and absf(absf(p.y) - WIDTH * 0.5) < 1e-3
		assert_bool(on_corner).override_failure_message("vertex %s is a sharp corner" % p).is_false()


func test_trimmed_roads_do_not_reach_the_centre() -> void:
	var graph := _cross_graph()
	var junctions := JunctionBuilder.build_all(graph)
	var result := RoadMeshBuilder.build(graph, junctions)
	assert_int(result.edges_built).is_equal(4)
	assert_int(result.junctions_built).is_equal(1)
	var chunk := Vector2i(0, 0)
	for v in result.roads[chunk].vertices:
		assert_bool(absf(v.x) >= WIDTH * 0.5 or absf(v.z) >= WIDTH * 0.5).override_failure_message("road vertex %s inside junction" % v).is_true()


func test_shallow_ramp_merge_stays_compact() -> void:
	# A ramp leaving a motorway at 8 degrees: side lines meet ~60 m away, the junction must not grow that far.
	var nodes := [
		{"id": "n_c", "position": [0, 0, 0], "ground_y": 0, "junction_type": "junction"},
		{"id": "n_w", "position": [-200, 0, 0], "ground_y": 0, "junction_type": "dead_end"},
		{"id": "n_e", "position": [200, 0, 0], "ground_y": 0, "junction_type": "dead_end"},
		{"id": "n_r", "position": [198, 0, 28], "ground_y": 0, "junction_type": "dead_end"},
	]
	var edges := []
	for arm in [["w", "n_w", [[0, 0, 0], [-200, 0, 0]], "motorway", 14.0], ["e", "n_e", [[0, 0, 0], [200, 0, 0]], "motorway", 14.0], ["r", "n_r", [[0, 0, 0], [198, 0, 28]], "motorway_link", 7.0]]:
		edges.append({
			"id": "w%s.0" % arm[0], "from": "n_c", "to": arm[1], "polyline": arm[2], "class": arm[3],
			"lanes_forward": 2, "lanes_backward": 0, "oneway": true, "speed_kph": 100, "width_m": arm[4],
			"layer": 0, "bridge": false, "tunnel": false, "name": arm[0], "osm_way_id": 1, "defaulted_fields": [],
			"access": null, "length_m": 200.0,
		})
	var graph := RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})
	var j: JunctionBuilder.Junction = JunctionBuilder.build_all(graph)["n_c"]
	for eid in j.trims:
		assert_float(j.trims[eid]).override_failure_message("trim for %s is %.1f m" % [eid, j.trims[eid]]).is_less(7.0 * JunctionBuilder.MAX_CORNER_HALF_WIDTHS + 2.0)
	for p in j.polygon_xz:
		assert_float(p.length()).is_less(30.0)


func test_corners_are_rounded() -> void:
	var graph := _cross_graph()
	var j: JunctionBuilder.Junction = JunctionBuilder.build_all(graph)["n_c"]
	# 4 arms x (2 caps + FILLET_STEPS curve points)
	assert_int(j.polygon_xz.size()).is_equal(4 * (2 + JunctionBuilder.FILLET_STEPS))
	assert_int(Geometry2D.triangulate_polygon(j.polygon_xz).size()).is_greater(0)
	# Curve points hug their sharp corner (within the 0.5 m cap margin) without landing on it.
	var curve_points := 0
	for p in j.polygon_xz:
		var corner := Vector2(signf(p.x) * WIDTH * 0.5, signf(p.y) * WIDTH * 0.5)
		var d := p.distance_to(corner)
		if absf(p.x) > WIDTH * 0.5 - 1e-3 and absf(p.y) > WIDTH * 0.5 - 1e-3 and d < JunctionBuilder.TRIM_MARGIN_M - 1e-3:
			assert_float(d).is_greater(1e-3)
			curve_points += 1
	assert_int(curve_points).is_equal(4 * JunctionBuilder.FILLET_STEPS)


func test_near_parallel_arms_share_a_slot_and_leave_no_sliver() -> void:
	# A wide road and a narrow one leave the node 3 degrees apart; a third arm goes the other way.
	var nodes := [
		{"id": "n_c", "position": [0, 0, 0], "ground_y": 0, "junction_type": "junction"},
		{"id": "n_w", "position": [-100, 0, 0], "ground_y": 0, "junction_type": "dead_end"},
		{"id": "n_a", "position": [100, 0, 0], "ground_y": 0, "junction_type": "dead_end"},
		{"id": "n_b", "position": [100, 0, 5], "ground_y": 0, "junction_type": "dead_end"},
	]
	var edges := [
		{"id": "ww.0", "from": "n_c", "to": "n_w", "polyline": [[0, 0, 0], [-100, 0, 0]], "width_m": 14.0, "lanes_forward": 2, "lanes_backward": 2},
		{"id": "wa.0", "from": "n_c", "to": "n_a", "polyline": [[0, 0, 0], [100, 0, 0]], "width_m": 14.0, "lanes_forward": 2, "lanes_backward": 2},
		{"id": "wb.0", "from": "n_c", "to": "n_b", "polyline": [[0, 0, 0], [100, 0, 5]], "width_m": 7.0, "lanes_forward": 1, "lanes_backward": 1},
	]
	for e in edges:
		e.merge({"class": "primary", "oneway": false, "speed_kph": 50, "layer": 0, "bridge": false, "tunnel": false, "name": e["id"], "osm_way_id": 1, "defaulted_fields": [], "access": null, "length_m": 100.0})
	var graph := RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})
	var j: JunctionBuilder.Junction = JunctionBuilder.build_one(graph, "n_c")
	assert_bool(j.fallback_hull).is_false()
	# Two slots in the walk: 2 caps + fillet per slot.
	assert_int(j.polygon_xz.size()).is_equal(2 * (2 + JunctionBuilder.FILLET_STEPS))
	for p in j.polygon_xz:
		assert_float(p.length()).override_failure_message("vertex %s is far from the node" % p).is_less(20.0)
	assert_float(j.trims["wb.0"]).is_equal_approx(j.trims["wa.0"], 1e-4)


func test_hull_junction_on_a_slope_follows_its_arms() -> void:
	# Eight arms (a hull fallback) on a hillside: the east arms climb 2 m over 50 m, the west
	# arms drop; hull vertices must sit on their arm's grade, not flat at the node's height.
	var nodes := [{"id": "n_c", "position": [0, 10, 0], "ground_y": 10, "junction_type": "junction"}]
	var edges := []
	for k in range(8):
		var ang := TAU * k / 8.0
		var ex := cos(ang) * 50.0
		var ez := sin(ang) * 50.0
		var ey := 10.0 + 2.0 * cos(ang)  # east high, west low
		var nid := "n_%d" % k
		nodes.append({"id": nid, "position": [ex, ey, ez], "ground_y": ey, "junction_type": "dead_end"})
		edges.append({
			"id": "w%d.0" % k, "from": "n_c", "to": nid, "polyline": [[0, 10, 0], [ex, ey, ez]], "class": "residential",
			"lanes_forward": 1, "lanes_backward": 1, "oneway": false, "speed_kph": 40, "width_m": 7.0, "layer": 0, "bridge": false,
			"tunnel": false, "name": "w%d" % k, "osm_way_id": k, "defaulted_fields": [], "access": null, "length_m": 50.0,
		})
	var graph := RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})
	# The hull height rule itself, as the hull fallback applies it to each vertex.
	var node: RoadGraph.RoadNode = graph.nodes["n_c"]
	var arms: Array[Dictionary] = []
	for eid in graph.incident("n_c"):
		var e: RoadGraph.RoadEdge = graph.edges[eid]
		var dir := graph.direction_from(e, "n_c")
		arms.append({"edge": eid, "dir": dir, "angle": atan2(dir.y, dir.x), "hw": e.width_m * 0.5})
	var east := JunctionBuilder._hull_height(graph, node, arms, Vector2(20.0, 0.0))
	var west := JunctionBuilder._hull_height(graph, node, arms, Vector2(-20.0, 0.0))
	var centre := JunctionBuilder._hull_height(graph, node, arms, Vector2(0.0, 0.0))
	assert_float(east).is_equal_approx(10.8, 0.05)  # 20 m up a 2 m per 50 m climb
	assert_float(west).is_equal_approx(9.2, 0.05)
	assert_float(centre).is_equal_approx(10.0, 1e-4)


func _divided_graph() -> RoadGraph:
	# A merged junction at the origin: two one-way carriageways 12 m apart (z = -6 eastbound,
	# z = +6 westbound) end on their own lines beside the node, as the importer leaves them, and a
	# two-way cross street ends at the node itself.
	var nodes := [{"id": "c1", "position": [0, 0, 0], "ground_y": 0, "junction_type": "junction"}]
	var edges := []
	var arms := [
		["e_in", "n_ew", "c1", [[-100, 0, -6], [0, 0, -6]], 7.0, true],
		["e_out", "c1", "n_ee", [[0, 0, -6], [100, 0, -6]], 7.0, true],
		["w_in", "n_we", "c1", [[100, 0, 6], [0, 0, 6]], 7.0, true],
		["w_out", "c1", "n_ww", [[0, 0, 6], [-100, 0, 6]], 7.0, true],
		["x_s", "c1", "n_s", [[0, 0, 0], [0, 0, -100]], 8.0, false],
		["x_n", "c1", "n_n", [[0, 0, 0], [0, 0, 100]], 8.0, false],
	]
	for arm in arms:
		var far: Array = arm[3][0] if arm[2] == "c1" else arm[3][1]
		var far_id: String = arm[1] if arm[2] == "c1" else arm[2]
		nodes.append({"id": far_id, "position": far, "ground_y": 0, "junction_type": "dead_end"})
		edges.append({
			"id": arm[0], "from": arm[1], "to": arm[2], "polyline": arm[3], "class": "primary",
			"lanes_forward": 2 if arm[5] else 1, "lanes_backward": 0 if arm[5] else 1, "oneway": arm[5], "speed_kph": 50,
			"width_m": arm[4], "layer": 0, "bridge": false, "tunnel": false, "name": arm[0], "osm_way_id": 1,
			"defaulted_fields": [], "access": null, "length_m": 100.0,
		})
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})


func test_offset_arms_keep_each_carriageway_on_its_own_line() -> void:
	var graph := _divided_graph()
	var j: JunctionBuilder.Junction = JunctionBuilder.build_one(graph, "c1")
	assert_bool(j.fallback_hull).is_false()
	assert_bool(JunctionBuilder._is_simple(j.polygon_xz)).is_true()
	assert_int(Geometry2D.triangulate_polygon(j.polygon_xz).size()).is_greater(0)
	# Carriageways are trimmed at the cross street's side plus the margin; the cross street runs
	# out past the far side of each carriageway.
	for eid in ["e_in", "e_out", "w_in", "w_out"]:
		assert_float(j.trims[eid]).is_equal_approx(4.0 + JunctionBuilder.TRIM_MARGIN_M, 1e-3)
	for eid in ["x_s", "x_n"]:
		assert_float(j.trims[eid]).is_equal_approx(6.0 + 3.5 + JunctionBuilder.TRIM_MARGIN_M, 1e-3)
	# Each carriageway's cap sits across its own line, not across the node.
	for cap in [Vector2(7, -9.5), Vector2(7, -2.5), Vector2(-7, 2.5), Vector2(-7, 9.5), Vector2(-7, -2.5), Vector2(7, 2.5)]:
		var found := false
		for p in j.polygon_xz:
			found = found or p.distance_to(cap) < 1e-3
		assert_bool(found).override_failure_message("no cap vertex at %s" % cap).is_true()
	# The cross street is paved through the median; the median beyond the junction is not.
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(3.9, 0.0), j.polygon_xz)).is_true()
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(-3.9, 0.0), j.polygon_xz)).is_true()
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(9.0, 0.0), j.polygon_xz)).is_false()
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(-9.0, 0.0), j.polygon_xz)).is_false()


func test_offset_arms_build_straight_ribbons_and_lanes() -> void:
	var graph := _divided_graph()
	var junctions := JunctionBuilder.build_all(graph)
	var result := RoadMeshBuilder.build(graph, junctions)
	assert_int(result.junctions_built).is_equal(1)
	# Through traffic on each carriageway holds its own carriageway (|z| between 2.5 and 9.5 m)
	# all the way through instead of steering toward the node at z = 0.
	var lanes := LaneGraph.build(graph, junctions)
	var through := 0
	for lp in lanes.paths:
		var run := lp.points[lp.points.size() - 1] - lp.points[0]
		if not lp.is_connector or lp.straightness < 0.99 or absf(run.x) < absf(run.z):
			continue  # turns and the cross street
		through += 1
		for p in lp.points:
			assert_float(absf(p.z)).override_failure_message("connector leaves its carriageway at %s" % p).is_between(2.5, 9.5)
	assert_int(through).is_greater(0)


func test_big_junction_on_a_crest_does_not_sag_below_its_node() -> void:
	# The divided crossing on a crest: every arm drops 1 m over its 100 m. The junction surface
	# must reach the node's height in the middle, not sag to its boundary heights.
	var graph := _divided_graph()
	for e in graph.edges.values():
		var pl: PackedVector3Array = e.polyline
		for k in range(pl.size()):
			var p := pl[k]
			pl[k] = Vector3(p.x, 10.0 - Vector2(p.x, p.z).length() / 100.0, p.z)
		e.polyline = pl
	graph.nodes["c1"].position = Vector3(0, 10, 0)
	var junctions := JunctionBuilder.build_all(graph)
	var result := RoadMeshBuilder.build(graph, junctions)
	var top := -INF
	for v in result.junctions[Vector2i(0, 0)].vertices:
		if Vector2(v.x, v.z).length() < 0.5:
			top = maxf(top, v.y)
	assert_float(top).is_equal_approx(10.0 + RoadMeshBuilder.SURFACE_LIFT_M, 1e-3)
