

func _fork_graph() -> RoadGraph:
	# A one-way through road split at a fork node, with a narrower ramp leaving on the +z side.
	# The importer has already peeled the ramp's start 4.5 m off the centreline.
	var nodes := [
		{"id": "n_a", "position": [-200, 0, 0], "ground_y": 0, "junction_type": "dead_end"},
		{"id": "n_f", "position": [0, 0, 0], "ground_y": 0, "junction_type": "fork"},
		{"id": "n_b", "position": [200, 0, 0], "ground_y": 0, "junction_type": "dead_end"},
		{"id": "n_r", "position": [200, 0, 60], "ground_y": 0, "junction_type": "dead_end"},
	]
	var edges := [
		{"id": "w1.0", "from": "n_a", "to": "n_f", "polyline": [[-200, 0, 0], [0, 0, 0]], "class": "motorway", "width_m": 14.0, "lanes_forward": 4, "lanes_backward": 0},
		{"id": "w1.1", "from": "n_f", "to": "n_b", "polyline": [[0, 0, 0], [200, 0, 0]], "class": "motorway", "width_m": 10.5, "lanes_forward": 3, "lanes_backward": 0},
		{"id": "w2.0", "from": "n_f", "to": "n_r", "polyline": [[0, 0, 4.5], [40, 0, 9.5], [200, 0, 60]], "class": "motorway_link", "width_m": 5.0, "lanes_forward": 1, "lanes_backward": 0},
	]
	for e in edges:
		e.merge({"oneway": true, "speed_kph": 100, "layer": 0, "bridge": false, "tunnel": false, "name": e["id"], "osm_way_id": 1, "defaulted_fields": [], "access": null, "length_m": 200.0})
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})


func test_fork_has_no_junction_polygon_and_the_through_road_tapers() -> void:
	var graph := _fork_graph()
	assert_bool(graph.is_fork("n_f")).is_true()
	var junctions := JunctionBuilder.build_all(graph)
	assert_bool(junctions.has("n_f")).is_false()
	assert_str(graph.through_partner(graph.edges["w1.0"], "n_f")).is_equal("w1.1")
	assert_str(graph.through_partner(graph.edges["w2.0"], "n_f")).is_equal("")
	# The wider incoming edge narrows to the outgoing width at the fork; the ramp does not taper.
	var taper := RoadMeshBuilder.taper_for(graph, graph.edges["w1.0"], junctions)
	assert_float(taper["end"]).is_equal_approx(10.5 * 0.5, 1e-4)
	assert_float(taper["start"]).is_equal(-1.0)
	var ramp_taper := RoadMeshBuilder.taper_for(graph, graph.edges["w2.0"], junctions)
	assert_float(ramp_taper["start"]).is_equal(-1.0)
	# Lane connectors across the fork carry no junction claim, so highway traffic never stops there.
	var lanes := LaneGraph.build(graph, junctions)
	for lp in lanes.paths:
		if lp.is_connector:
			assert_str(lp.junction_node).is_equal("")
