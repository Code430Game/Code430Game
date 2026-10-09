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


## Connectors leaving `lane` as {target lane id: lateral shift in metres}.
func _targets(lg: LaneGraph, lane: LaneGraph.LanePath) -> Dictionary:
	var out := {}
	for cid in lane.next:
		var c: LaneGraph.LanePath = lg.paths[cid]
		var t: LaneGraph.LanePath = lg.paths[c.next[0]]
		out[t.id] = absf(t.points[0].z - lane.points[lane.points.size() - 1].z)
	return out


func _lanes_of(lg: LaneGraph, edge_id: String) -> Array:
	return lg.paths.filter(func(p: LaneGraph.LanePath) -> bool: return not p.is_connector and p.edge_id == edge_id)


func test_a_road_continuing_past_a_node_keeps_each_car_in_its_lane() -> void:
	# #93, #107: two lanes eastbound, split into two edges at x = 100. Each lane goes on into
	# the lane beside it, never across to the other one.
	var g := _graph([
		{"id": "w1.0", "pl": [[0, 0, 0], [100, 0, 0]], "lf": 2, "lb": 0, "w": 7.0},
		{"id": "w2.0", "pl": [[100, 0, 0], [200, 0, 0]], "lf": 2, "lb": 0, "w": 7.0},
	])
	var lg := LaneGraph.build(g, {})
	for lane in _lanes_of(lg, "w1.0"):
		var t := _targets(lg, lane)
		assert_int(t.size()).is_equal(1)
		assert_float(t.values()[0]).is_less(0.1)


func test_an_added_lane_is_fed_and_a_dropped_lane_merges() -> void:
	var g := _graph([
		{"id": "w1.0", "pl": [[0, 0, 0], [100, 0, 0]], "lf": 1, "lb": 0, "w": 3.5},
		{"id": "w2.0", "pl": [[100, 0, 0], [200, 0, 0]], "lf": 2, "lb": 0, "w": 7.0},
		{"id": "w3.0", "pl": [[200, 0, 0], [300, 0, 0]], "lf": 1, "lb": 0, "w": 3.5},
	])
	var lg := LaneGraph.build(g, {})
	var one: LaneGraph.LanePath = _lanes_of(lg, "w1.0")[0]
	assert_int(_targets(lg, one).size()).is_equal(2)  # the new lane starts from the only lane there was
	for lane in _lanes_of(lg, "w2.0"):
		assert_int(_targets(lg, lane).size()).is_equal(1)  # both lanes go on into the single lane


func test_a_turn_still_reaches_every_lane_of_the_road_it_turns_into() -> void:
	var g := _graph([
		{"id": "w1.0", "pl": [[-100, 0, 0], [0, 0, 0]], "lf": 1, "lb": 0, "w": 3.5},
		{"id": "w2.0", "pl": [[0, 0, 0], [0, 0, 100]], "lf": 2, "lb": 0, "w": 7.0},
	])
	var lg := LaneGraph.build(g, {})
	assert_int(_targets(lg, _lanes_of(lg, "w1.0")[0]).size()).is_equal(2)


func test_in_ottawa_a_car_going_straight_on_joins_the_nearest_lane() -> void:
	# Each straight-on connector leads into the lane of the next road that starts nearest where
	# the car's lane ends, or feeds a lane that only starts there (nothing else reaches it).
	# Before #93 / #107 a car could take any lane of the next road, hopping across.
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack("code430.ottawa-centretown"))).is_true()
	var lg := LaneGraph.build(pack.graph, pack.junctions)
	var lanes_of_road := {}
	for p in lg.paths:
		if not p.is_connector:
			if not lanes_of_road.has(p.edge_id):
				lanes_of_road[p.edge_id] = []
			lanes_of_road[p.edge_id].append(p)
	var feeders := {}  # lane id -> lanes whose straight-on connectors reach it
	var from_lane := {}  # connector id -> the lane it leaves
	for p in lg.paths:
		if p.is_connector:
			continue
		for cid in p.next:
			from_lane[cid] = p
			var t: int = lg.paths[cid].next[0]
			var tl: LaneGraph.LanePath = lg.paths[t]
			if tl.edge_id == p.edge_id or p.direction_at(p.length).dot(tl.direction_at(0.0)) < LaneGraph.THROUGH_COS:
				continue  # only straight-on feeders count: a turn may also reach a new lane
			if not feeders.has(t):
				feeders[t] = []
			feeders[t].append(p.id)
	var bad := 0
	var example := ""
	var checked := 0
	for c in lg.paths:
		if not c.is_connector or c.next.is_empty() or not from_lane.has(c.id):
			continue
		var a: LaneGraph.LanePath = from_lane[c.id]
		var b: LaneGraph.LanePath = lg.paths[c.next[0]]
		if b.edge_id == a.edge_id or a.direction_at(a.length).dot(b.direction_at(0.0)) < LaneGraph.THROUGH_COS:
			continue  # a turn or a U-turn
		checked += 1
		var end := a.points[a.points.size() - 1]
		var same_way := (lanes_of_road[b.edge_id] as Array).filter(func(l: LaneGraph.LanePath) -> bool: return l.direction_at(0.0).dot(b.direction_at(0.0)) > 0.0)
		var nearest: LaneGraph.LanePath = LaneGraph._nearest_start(same_way, end)  # lanes leaving this end of the road
		if nearest != b and (feeders[b.id] as Array).size() > 1:
			bad += 1
			example = "lane %d (%s) into lane %d of %s at %s" % [a.id, a.edge_id, b.id, b.edge_id, end.snapped(Vector3.ONE)]
	assert_int(checked).is_greater(5000)
	assert_int(bad).override_failure_message("%d straight-on connectors hop a lane, e.g. %s" % [bad, example]).is_equal(0)
