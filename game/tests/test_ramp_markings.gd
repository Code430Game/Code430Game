extends GdUnitTestSuite
## Ramps give way to the road they meet (human, 2026-10-07: "the on ramp's lane markings are
## displayed interwoven with the highways lane markings"). Links used to sit 1.5 cm above every
## other road and every marking shared one height, so where a ramp's ribbon lay over the 417 its
## surface covered the motorway's and both sets of lines showed, crossed. Now a ramp's ribbon
## sits under the through road's, its markings stop where the through road covers them, and the
## through road's edge line turns to dashes across the ramp's mouth.

const PACK_ID := "code430.ottawa-centretown"


func _edge(id: String, from: String, to: String, pts: Array, road_class: String, lanes: int, width: float) -> Dictionary:
	return {
		"id": id, "from": from, "to": to, "polyline": pts, "class": road_class,
		"lanes_forward": lanes, "lanes_backward": 0, "oneway": true, "speed_kph": 100, "width_m": width,
		"layer": 0, "bridge": false, "tunnel": false, "name": "T", "osm_way_id": 1, "defaulted_fields": [],
		"access": null, "length_m": 100.0,
	}


## A two-lane motorway along x with an off-ramp leaving its centreline at a shallow angle, the
## way OSM draws it: the ramp's first metres lie on the motorway.
func _diverge() -> RoadGraph:
	var nodes := [
		{"id": "n_a", "position": [0, 0, 0], "ground_y": 0, "junction_type": "dead_end"},
		{"id": "n_f", "position": [100, 0, 0], "ground_y": 0, "junction_type": "fork"},
		{"id": "n_b", "position": [200, 0, 0], "ground_y": 0, "junction_type": "dead_end"},
		{"id": "n_r", "position": [190, 0, 30], "ground_y": 0, "junction_type": "dead_end"},
	]
	var edges := [
		_edge("w1.0", "n_a", "n_f", [[0, 0, 0], [100, 0, 0]], "motorway", 2, 8.0),
		_edge("w2.0", "n_f", "n_b", [[100, 0, 0], [200, 0, 0]], "motorway", 2, 8.0),
		_edge("w3.0", "n_f", "n_r", [[100, 0, 0], [150, 0, 4], [190, 0, 30]], "motorway_link", 1, 5.0),
	]
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})


func _builder(clip: bool) -> MarkingBuilder:
	var b := MarkingBuilder.new()
	assert_bool(b.load_rules()).is_true()
	b.clip_ramps = clip
	return b


## Ramp-marking vertices lying on a through road's ribbon, more than `inside_m` in from its edge.
## A vertex is a ramp marking's when it sits a ramp marking's lift above a ramp's ribbon (within a
## centimetre) and not a through marking's lift above a through road (a through road 3 cm below a
## ramp puts its own lines at that height too).
func _ramp_marks_on_through_roads(graph: RoadGraph, junctions: Dictionary, buckets: Dictionary, inside_m: float = 0.1) -> int:
	var exact := _builder(true)
	exact.rules["cover_max_dy_m"] = 0.01
	var inside := _builder(true)
	var ramps := {}
	var through := {}
	var through_inside := {}
	for eid in graph.sorted_edge_ids():
		var e: RoadGraph.RoadEdge = graph.edges[eid]
		var shape := inside._shape(graph, e, junctions)
		if shape.is_empty():
			continue
		if RoadMeshBuilder.is_link(e):
			exact._index_ribbon(shape, ramps)
		else:
			exact._index_ribbon(shape, through)
			shape["base_hw"] = float(shape["base_hw"]) - inside_m  # only well inside the ribbon
			inside._index_ribbon(shape, through_inside)
	var ramp_lift := exact.marking_lift(graph.edges[_first_link(graph)])
	var through_lift := exact.marking_lift(null)
	var n := 0
	for chunk in buckets:
		var tris: RoadMeshBuilder.ChunkTriangles = buckets[chunk]
		for v in tris.vertices:
			var p := v - Vector3(0.0, ramp_lift, 0.0)
			if exact.covered(ramps, p) and inside.covered(through_inside, p) and not exact.covered(through, v - Vector3(0.0, through_lift, 0.0)):
				n += 1
	return n


func _first_link(graph: RoadGraph) -> String:
	for eid in graph.sorted_edge_ids():
		if RoadMeshBuilder.is_link(graph.edges[eid]):
			return eid
	return ""


func test_a_ramp_sits_under_the_road_it_leaves() -> void:
	var g := _diverge()
	assert_float(RoadMeshBuilder.surface_lift(g.edges["w3.0"])).is_less(RoadMeshBuilder.surface_lift(g.edges["w1.0"]) - 0.01)
	assert_float(RoadMeshBuilder.GORE_LIFT_M).is_less(RoadMeshBuilder.surface_lift(g.edges["w3.0"]))
	var b := _builder(true)
	# Ramp lines sit under the motorway's surface; the motorway's lines stay above everything.
	assert_float(b.marking_lift(g.edges["w3.0"])).is_less(RoadMeshBuilder.surface_lift(g.edges["w1.0"]))
	assert_float(b.marking_lift(g.edges["w1.0"])).is_greater(RoadMeshBuilder.surface_lift(g.edges["w1.0"]))


func test_ramp_markings_stop_where_the_motorway_covers_them() -> void:
	var g := _diverge()
	var before := _ramp_marks_on_through_roads(g, {}, _builder(false).build(g, {}))
	assert_int(before).override_failure_message("the fixture should have ramp lines on the motorway to clip").is_greater(0)
	var after := _ramp_marks_on_through_roads(g, {}, _builder(true).build(g, {}))
	assert_int(after).is_equal(0)


func test_the_motorway_edge_line_breaks_across_the_ramp_mouth() -> void:
	var g := _diverge()
	var solid := _ramp_side_edge_length(_builder(false).build(g, {}))
	var broken := _ramp_side_edge_length(_builder(true).build(g, {}))
	# Where the ramp's ribbon lies over that line (x about 117 to 153), the motorway's edge line on
	# the ramp's side becomes dashes: about a third of the solid line's paint.
	assert_float(solid).is_greater(29.0)
	assert_float(broken).is_greater(5.0)
	assert_float(broken).is_less(solid * 0.6)


## Painted length of the motorway's edge line on the ramp's side (z about +3.88) between x 120
## and 150. Each quad is two triangles: a0 b0 a1, then a1 b0 b1.
func _ramp_side_edge_length(buckets: Dictionary) -> float:
	var length := 0.0
	for chunk in buckets:
		var tris: RoadMeshBuilder.ChunkTriangles = buckets[chunk]
		for t in range(0, tris.vertices.size(), 6):
			var a0 := tris.vertices[t]
			var b0 := tris.vertices[t + 1]
			if absf(a0.z - 3.88) < 0.2 and absf(b0.z - 3.88) < 0.2:
				length += maxf(0.0, minf(maxf(a0.x, b0.x), 150.0) - maxf(minf(a0.x, b0.x), 120.0))
	return length


func test_ottawa_has_no_ramp_lines_on_through_roads() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack(PACK_ID))).is_true()
	var before := _ramp_marks_on_through_roads(pack.graph, pack.junctions, _builder(false).build(pack.graph, pack.junctions))
	var after := _ramp_marks_on_through_roads(pack.graph, pack.junctions, _builder(true).build(pack.graph, pack.junctions))
	print("ramp marking vertices on through roads: %d without clipping, %d with" % [before, after])
	assert_int(before).is_greater(100)
	assert_int(after).is_less_equal(before / 50)
