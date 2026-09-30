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
	assert_int(j.polygon_xz.size()).is_equal(12)
	for eid in ["we.0", "ww.0", "wn.0", "ws.0"]:
		assert_float(j.trims[eid]).is_equal_approx(WIDTH * 0.5 + JunctionBuilder.TRIM_MARGIN_M, 1e-4)
	assert_int(Geometry2D.triangulate_polygon(j.polygon_xz).size()).is_greater(0)
	var corners := 0
	for p in j.polygon_xz:
		if absf(absf(p.x) - WIDTH * 0.5) < 1e-4 and absf(absf(p.y) - WIDTH * 0.5) < 1e-4:
			corners += 1
	assert_int(corners).is_equal(4)


func test_trimmed_roads_do_not_reach_the_centre() -> void:
	var graph := _cross_graph()
	var junctions := JunctionBuilder.build_all(graph)
	var result := RoadMeshBuilder.build(graph, junctions)
	assert_int(result.edges_built).is_equal(4)
	assert_int(result.junctions_built).is_equal(1)
	var chunk := Vector2i(0, 0)
	for v in result.roads[chunk].vertices:
		assert_bool(absf(v.x) >= WIDTH * 0.5 or absf(v.z) >= WIDTH * 0.5).override_failure_message("road vertex %s inside junction" % v).is_true()
