extends GdUnitTestSuite
## Lane paths: offsets, directions, legal connectors, dead-end U-turns.


func _graph(specs: Array) -> RoadGraph:
	var nodes := {}
	var edges := []
	for spec in specs:
		var pl: Array = spec["pl"]
		for p in [pl[0], pl[pl.size() - 1]]:
			var id := "n_%d_%d" % [int(p[0]), int(p[2])]
			nodes[id] = {"id": id, "position": p, "ground_y": 0, "junction_type": "junction"}
		edges.append({
			"id": spec["id"], "from": "n_%d_%d" % [int(pl[0][0]), int(pl[0][2])], "to": "n_%d_%d" % [int(pl[pl.size() - 1][0]), int(pl[pl.size() - 1][2])],
			"polyline": pl, "class": spec.get("class", "secondary"), "lanes_forward": spec.get("lf", 1), "lanes_backward": spec.get("lb", 1),
			"oneway": spec.get("lb", 1) == 0, "speed_kph": 50, "width_m": spec.get("w", 7.0), "layer": 0, "bridge": false, "tunnel": false,
			"name": spec["id"], "osm_way_id": 1, "defaulted_fields": [], "access": null, "length_m": 100.0,
		})
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes.values(), "edges": edges, "pedestrian_ways": []})


func test_two_way_road_lanes_on_the_right() -> void:
	var g := _graph([{"id": "w1.0", "pl": [[0, 0, 0], [100, 0, 0]], "lf": 1, "lb": 1, "w": 7.0}])
	var lg := LaneGraph.build(g, {})
	var lanes := lg.paths.filter(func(p: LaneGraph.LanePath) -> bool: return not p.is_connector)
	assert_int(lanes.size()).is_equal(2)
	var fwd: LaneGraph.LanePath = lanes[0]
	var back: LaneGraph.LanePath = lanes[1]
	# Travelling +x, right of travel is +z (south): the forward lane sits at z = +1.75.
	assert_float(fwd.points[0].z).is_equal_approx(1.75, 1e-4)
	assert_float(fwd.points[0].x).is_less(fwd.points[fwd.points.size() - 1].x)
	assert_float(back.points[0].z).is_equal_approx(-1.75, 1e-4)
	assert_float(back.points[0].x).is_greater(back.points[back.points.size() - 1].x)
	assert_float(fwd.length).is_equal_approx(100.0, 1e-3)


func test_one_way_three_lanes() -> void:
	var g := _graph([{"id": "w1.0", "pl": [[0, 0, 0], [100, 0, 0]], "lf": 3, "lb": 0, "w": 10.5}])
	var lg := LaneGraph.build(g, {})
	var zs := []
	for p in lg.paths:
		if not p.is_connector:
			zs.append(snappedf(p.points[0].z, 0.01))
			assert_float(p.points[0].x).is_less(p.points[1].x)
	assert_array(zs).contains_exactly_in_any_order([-3.5, 0.0, 3.5])


func test_cross_connectors_are_legal_and_prefer_straight() -> void:
	# Two-way east-west, one-way northbound (toward -z) north-south.
	var g := _graph([
		{"id": "w1.0", "pl": [[-100, 0, 0], [0, 0, 0]]},
		{"id": "w2.0", "pl": [[0, 0, 0], [100, 0, 0]]},
		{"id": "w3.0", "pl": [[0, 0, 100], [0, 0, 0]], "lf": 1, "lb": 0},
		{"id": "w4.0", "pl": [[0, 0, 0], [0, 0, -100]], "lf": 1, "lb": 0},
	])
	var lg := LaneGraph.build(g, JunctionBuilder.build_all(g))
	# The eastbound lane of w1 arriving at the centre may go: straight (w2 fwd), left/north (w4), but not w3 (one-way toward the centre).
	var east: LaneGraph.LanePath = null
	for p in lg.paths:
		if p.edge_id == "w1.0" and p.points[0].x < p.points[p.points.size() - 1].x:
			east = p
	assert_object(east).is_not_null()
	var targets := []
	var best_straight := -2.0
	var best_target := ""
	for cid in east.next:
		var c: LaneGraph.LanePath = lg.paths[cid]
		assert_bool(c.is_connector).is_true()
		var t: LaneGraph.LanePath = lg.paths[c.next[0]]
		targets.append(t.edge_id)
		if c.straightness > best_straight:
			best_straight = c.straightness
			best_target = t.edge_id
	assert_array(targets).contains_exactly_in_any_order(["w2.0", "w4.0"])  # no U-turn while other exits exist
	assert_str(best_target).is_equal("w2.0")


func test_dead_end_gets_a_u_turn() -> void:
	var g := _graph([{"id": "w1.0", "pl": [[0, 0, 0], [100, 0, 0]]}])
	var lg := LaneGraph.build(g, {})
	var fwd: LaneGraph.LanePath = lg.paths[0]
	assert_int(fwd.next.size()).is_equal(1)
	var u: LaneGraph.LanePath = lg.paths[fwd.next[0]]
	assert_bool(u.is_connector).is_true()
	var back: LaneGraph.LanePath = lg.paths[u.next[0]]
	assert_str(back.edge_id).is_equal("w1.0")
	assert_float(back.points[0].x).is_greater(back.points[back.points.size() - 1].x)


func test_position_and_direction_along_path() -> void:
	var g := _graph([{"id": "w1.0", "pl": [[0, 0, 0], [50, 0, 0], [50, 0, 50]], "lf": 1, "lb": 0, "w": 3.0}])
	var lg := LaneGraph.build(g, {})
	var p: LaneGraph.LanePath = lg.paths[0]
	assert_float(p.length).is_equal_approx(100.0, 0.5)
	assert_that(p.position_at(25.0)).is_equal_approx(Vector3(25, 0, 0), Vector3(0.6, 0.1, 0.6))
	assert_that(p.direction_at(80.0)).is_equal_approx(Vector3(0, 0, 1), Vector3(0.05, 0.05, 0.05))
