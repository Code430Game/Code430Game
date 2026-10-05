extends GdUnitTestSuite
## Zebra crossings: bars across the carriageway inside its edges, long side along the road;
## a stop line for traffic heading into a signalised junction.


func _graph(signals: bool) -> RoadGraph:
	var nodes := [
		{"id": "a", "position": [0.0, 70.0, 0.0], "ground_y": 70, "junction_type": "dead_end"},
		{"id": "b", "position": [70.0, 70.0, 0.0], "ground_y": 70, "junction_type": "junction", "control": "signals" if signals else "none"},
	]
	var edges := [{"id": "w1.0", "from": "a", "to": "b", "polyline": [[0.0, 70.0, 0.0], [70.0, 70.0, 0.0]], "class": "secondary",
		"lanes_forward": 1, "lanes_backward": 1, "oneway": false, "speed_kph": 50, "width_m": 7.0, "layer": 0, "bridge": false,
		"tunnel": false, "name": "", "osm_way_id": 1, "defaulted_fields": [], "access": null, "length_m": 70.0, "bus": "", "bus_lane": -1}]
	var ways := [{"id": "p1", "class": "footway", "kind": "crossing", "width_m": 3.0, "polyline": [[50.0, 70.0, -6.0], [50.0, 70.0, 6.0]]}]
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": ways, "bus_stops": []})


func _vertices(buckets: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in buckets:
		out.append_array((buckets[k] as RoadMeshBuilder.ChunkTriangles).vertices)
	return out


func test_bars_cross_the_carriageway_inside_its_edges() -> void:
	var buckets := {}
	assert_int(MarkingBuilder.build_crossings(_graph(false), buckets, 0.02, Color.WHITE)).is_equal(1)
	var v := _vertices(buckets)
	assert_int(v.size()).is_equal(6 * 6)  # six bars of two triangles across a 7 m road
	for p in v:
		assert_float(absf(p.z)).is_less_equal(3.5 - MarkingBuilder.ZEBRA_EDGE_M + 0.001)  # inside the edges
		assert_float(absf(p.x - 50.0)).is_less_equal(1.5 + 0.001)  # as long as the crossing is wide
		assert_float(p.y).is_equal_approx(70.0 + SidewalkBuilder.SURFACE_LIFT_M + 0.008, 0.001)  # above the crossing strip


func test_a_signalised_junction_gets_a_stop_line_before_the_crossing() -> void:
	var plain := {}
	var lit := {}
	MarkingBuilder.build_crossings(_graph(false), plain, 0.02, Color.WHITE)
	MarkingBuilder.build_crossings(_graph(true), lit, 0.02, Color.WHITE)
	var extra := _vertices(lit).size() - _vertices(plain).size()
	assert_int(extra).is_equal(6)  # one more ribbon: the stop line
	# Traffic heads east into the junction at x = 70: the line sits west of the stripes, across
	# the eastbound lanes (right of travel is south, +z).
	var v := _vertices(lit)
	var line := v.slice(v.size() - 6)
	for p in line:
		assert_float(p.x).is_less(50.0 - 1.5)
		assert_float(p.z).is_greater_equal(-0.25)


func test_the_ottawa_pack_stripes_its_crossings() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack("code430.ottawa-centretown"))).is_true()
	var buckets := {}
	var striped := MarkingBuilder.build_crossings(pack.graph, buckets, 0.02, Color.WHITE)
	print("zebra: %d crossings striped" % striped)
	assert_int(striped).is_greater(800)
