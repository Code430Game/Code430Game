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
