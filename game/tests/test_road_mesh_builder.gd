extends GdUnitTestSuite
## Chunk seams: an edge crossing a chunk boundary shares identical vertices on both sides.


func _graph_one_edge() -> RoadGraph:
	var nodes := [
		{"id": "n_a", "position": [100, 0, 10], "ground_y": 0, "junction_type": "dead_end"},
		{"id": "n_b", "position": [400, 6, 40], "ground_y": 0, "junction_type": "dead_end"},
	]
	var edges := [{
		"id": "w1.0", "from": "n_a", "to": "n_b", "polyline": [[100, 0, 10], [400, 6, 40]], "class": "secondary",
		"lanes_forward": 2, "lanes_backward": 2, "oneway": false, "speed_kph": 50, "width_m": 14.0,
		"layer": 0, "bridge": false, "tunnel": false, "name": "Seam", "osm_way_id": 1, "defaulted_fields": [],
		"access": null, "length_m": 301.5,
	}]
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})


func test_seam_vertices_are_shared_exactly() -> void:
	var result := RoadMeshBuilder.build(_graph_one_edge(), {})
	assert_bool(result.roads.has(Vector2i(0, 0))).is_true()
	assert_bool(result.roads.has(Vector2i(1, 0))).is_true()
	var left := {}
	for v in result.roads[Vector2i(0, 0)].vertices:
		left[v] = true
	var shared := {}
	for v in result.roads[Vector2i(1, 0)].vertices:
		if left.has(v):
			shared[v] = true
	# The two ribbon corners on the chunk boundary are bit-identical in both chunks.
	assert_int(shared.size()).is_equal(2)
	for v in shared.keys():
		var centre_x: float = 256.0
		assert_float(absf((v as Vector3).x - centre_x)).is_less(7.5)


func test_mesh_has_normals_and_no_nan() -> void:
	var result := RoadMeshBuilder.build(_graph_one_edge(), {})
	var mesh: ArrayMesh = result.roads[Vector2i(0, 0)].to_mesh()
	var arrays := mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_int(normals.size()).is_greater(0)
	for n in normals:
		assert_bool(is_nan(n.x) or is_nan(n.y) or is_nan(n.z)).is_false()
		assert_float(n.y).is_greater(0.5)
