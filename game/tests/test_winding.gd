extends GdUnitTestSuite
## Every generated surface must face up under Godot's clockwise front-face rule,
## otherwise it is culled from above and one-sided trimesh collision lets things fall through.


func _mean_normal_y(mesh: ArrayMesh) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var total := 0.0
	var count := 0
	if indices.size() > 0:
		for t in range(0, indices.size(), 3):
			var a := verts[indices[t]]
			var b := verts[indices[t + 1]]
			var c := verts[indices[t + 2]]
			total += (c - a).cross(b - a).normalized().y  # Godot: clockwise = front
			count += 1
	else:
		for t in range(0, verts.size(), 3):
			total += (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t]).normalized().y
			count += 1
	return total / count if count > 0 else 0.0


func _cross_graph() -> RoadGraph:
	var edges := []
	var arms := [["e", [[0, 0, 0], [100, 0, 0]], "n_e"], ["w", [[0, 0, 0], [-100, 0, 0]], "n_w"], ["n", [[0, 0, 0], [0, 0, -100]], "n_n"], ["s", [[0, 0, 0], [0, 0, 100]], "n_s"]]
	var nodes := [{"id": "n_c", "position": [0, 0, 0], "ground_y": 0, "junction_type": "junction"}]
	for arm in arms:
		nodes.append({"id": arm[2], "position": arm[1][1], "ground_y": 0, "junction_type": "dead_end"})
		edges.append({
			"id": "w%s.0" % arm[0], "from": "n_c", "to": arm[2], "polyline": arm[1], "class": "residential",
			"lanes_forward": 1, "lanes_backward": 1, "oneway": false, "speed_kph": 40, "width_m": 8.0,
			"layer": 0, "bridge": false, "tunnel": false, "name": arm[0], "osm_way_id": 1, "defaulted_fields": [],
			"access": null, "length_m": 100.0,
		})
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})


func test_roads_face_up() -> void:
	var graph := _cross_graph()
	var result := RoadMeshBuilder.build(graph, JunctionBuilder.build_all(graph))
	assert_float(_mean_normal_y(result.roads[Vector2i(0, 0)].to_mesh())).is_greater(0.99)
	assert_float(_mean_normal_y(result.roads[Vector2i(-1, 0)].to_mesh())).is_greater(0.99)


func test_junctions_face_up() -> void:
	var graph := _cross_graph()
	var result := RoadMeshBuilder.build(graph, JunctionBuilder.build_all(graph))
	assert_float(_mean_normal_y(result.junctions[Vector2i(0, 0)].to_mesh())).is_greater(0.99)


func test_terrain_faces_up() -> void:
	var ch := TerrainBuilder.ChunkHeights.new()
	ch.cx = 0
	ch.cz = 0
	ch.samples = 5
	ch.resolution_m = 4.0
	ch.heights.resize(25)
	for i in range(25):
		ch.heights[i] = 10.0 + 0.1 * i
	for lod in range(3):
		assert_float(_mean_normal_y(TerrainBuilder.build_mesh(ch, lod))).is_greater(0.9)
	var arrays := TerrainBuilder.build_mesh(ch, 0).surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for n in normals:
		assert_float(n.y).is_greater(0.9)
