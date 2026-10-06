extends GdUnitTestSuite
## Lane marking rules and geometry on synthetic edges.


func _edge(road_class: String, lanes_f: int, lanes_b: int, width: float, length: float = 100.0) -> RoadGraph:
	var nodes := [
		{"id": "n_a", "position": [0, 0, 0], "ground_y": 0, "junction_type": "dead_end"},
		{"id": "n_b", "position": [length, 0, 0], "ground_y": 0, "junction_type": "dead_end"},
	]
	var edges := [{
		"id": "w1.0", "from": "n_a", "to": "n_b", "polyline": [[0, 0, 0], [length, 0, 0]], "class": road_class,
		"lanes_forward": lanes_f, "lanes_backward": lanes_b, "oneway": lanes_b == 0, "speed_kph": 50, "width_m": width,
		"layer": 0, "bridge": false, "tunnel": false, "name": "T", "osm_way_id": 1, "defaulted_fields": [],
		"access": null, "length_m": length,
	}]
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})


func _builder() -> MarkingBuilder:
	var b := MarkingBuilder.new()
	assert_bool(b.load_rules()).is_true()
	return b


func test_two_lane_residential_gets_no_lines() -> void:
	var b := _builder()
	var g := _edge("residential", 1, 1, 7.0)
	assert_int(b.lines_for(g.edges["w1.0"]).size()).is_equal(0)


func test_two_lane_tertiary_gets_centre_and_edges() -> void:
	var b := _builder()
	var lines := b.lines_for(_edge("tertiary", 1, 1, 7.0).edges["w1.0"])
	assert_int(lines.size()).is_equal(3)
	var yellow := lines.filter(func(l: Dictionary) -> bool: return l["color"] == "yellow")
	assert_int(yellow.size()).is_equal(1)
	assert_float(yellow[0]["offset"]).is_equal_approx(0.0, 1e-6)


func test_one_way_three_lane_motorway() -> void:
	var b := _builder()
	var lines := b.lines_for(_edge("motorway", 3, 0, 10.5).edges["w1.0"])
	var dashed := lines.filter(func(l: Dictionary) -> bool: return l["style"] == "dashed")
	var yellow := lines.filter(func(l: Dictionary) -> bool: return l["color"] == "yellow")
	assert_int(dashed.size()).is_equal(2)
	assert_int(yellow.size()).is_equal(0)
	assert_int(lines.size()).is_equal(4)
	var offsets := []
	for l in dashed:
		offsets.append(snappedf(l["offset"], 0.01))
	assert_array(offsets).contains_exactly_in_any_order([-1.75, 1.75])


func test_four_lane_primary_double_centre() -> void:
	var b := _builder()
	var lines := b.lines_for(_edge("primary", 2, 2, 14.0).edges["w1.0"])
	var yellow := lines.filter(func(l: Dictionary) -> bool: return l["color"] == "yellow")
	assert_int(yellow.size()).is_equal(2)
	assert_float(absf(yellow[0]["offset"] - yellow[1]["offset"])).is_equal_approx(0.24, 1e-6)
	var dashed := lines.filter(func(l: Dictionary) -> bool: return l["style"] == "dashed")
	assert_int(dashed.size()).is_equal(2)


func test_dash_count_and_winding() -> void:
	var b := _builder()
	var g := _edge("motorway", 2, 0, 7.0, 90.0)  # one dashed divider along 90 m: dashes at 0, 9, ... 81 -> 10 dashes
	var buckets := b.build(g, {})
	var total := 0.0
	var count := 0
	for chunk in buckets:  # the left edge line at z = -3.4 lands in chunk (0, -1)
		var tris: RoadMeshBuilder.ChunkTriangles = buckets[chunk]
		for t in range(0, tris.vertices.size(), 3):
			var a := tris.vertices[t]
			var bb := tris.vertices[t + 1]
			var c := tris.vertices[t + 2]
			total += (c - a).cross(bb - a).normalized().y
			count += 1
	assert_float(total / count).is_greater(0.99)
	# 2 edge lines (1 quad each = 2 tris) + 10 dashes (2 tris each) = 24 triangles
	assert_int(count).is_equal(24)


func test_markings_respect_junction_trims() -> void:
	var b := _builder()
	var g := _edge("secondary", 1, 1, 8.0)
	var j := JunctionBuilder.Junction.new()
	j.trims = {"w1.0": 20.0}
	var buckets := b.build(g, {"n_a": j})
	var min_x := INF
	for chunk in buckets:
		for v in buckets[chunk].vertices:
			min_x = minf(min_x, v.x)
	assert_float(min_x).is_greater_equal(20.0 - 1e-3)


## add-road-shoulders: a one-way motorway with 2 lanes, a 1 m left and a 2.5 m right shoulder
## (10.5 m paved): the lane line and the edge lines sit on the lanes, not the paved middle.
func test_motorway_lines_keep_to_the_lanes_inside_the_shoulders() -> void:
	var b := _builder()
	var g := _edge("motorway", 2, 0, 10.5)
	var e: RoadGraph.RoadEdge = g.edges["w1.0"]
	e.shoulder_left_m = 1.0
	e.shoulder_right_m = 2.5
	assert_float(e.carriageway_m()).is_equal_approx(7.0, 1e-6)
	assert_float(e.carriageway_offset()).is_equal_approx(-0.75, 1e-6)
	var lines := b.lines_for(e)
	var dashed := lines.filter(func(l: Dictionary) -> bool: return l["style"] == "dashed")
	assert_int(dashed.size()).is_equal(1)
	assert_float(dashed[0]["offset"]).is_equal_approx(-0.75, 1e-6)  # between the two lanes
	var solid := lines.filter(func(l: Dictionary) -> bool: return l["style"] == "solid")
	var edges := []
	for l in solid:
		edges.append(snappedf(l["offset"], 0.01))
	edges.sort()
	var lw := float(b.rules["line_width_m"])
	assert_float(edges[0]).is_equal_approx(-0.75 - 3.5 - lw * 0.5, 0.01)  # out on the left shoulder
	assert_float(edges[1]).is_equal_approx(-0.75 + 3.5 + lw * 0.5, 0.01)  # and the right
	assert_float(edges[1]).is_less(5.25 - 2.0)  # well inside the paved edge


func test_lanes_run_inside_the_shoulders() -> void:
	var g := _edge("motorway", 2, 0, 10.5)
	var e: RoadGraph.RoadEdge = g.edges["w1.0"]
	e.shoulder_left_m = 1.0
	e.shoulder_right_m = 2.5
	var lanes := LaneGraph.build(g, {})
	var offsets := []
	for lp in lanes.paths:
		if not lp.is_connector:
			offsets.append(snappedf(lp.points[0].z, 0.01))  # +z is right of travel along +x
	offsets.sort()
	assert_array(offsets).is_equal([-2.5, 1.0])
