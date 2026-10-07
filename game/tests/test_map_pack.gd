extends GdUnitTestSuite
## Loads the first-party Ottawa pack from the repo and checks chunks, terrain, collision, GLB round trip.

const PACK_ID := "code430.ottawa-centretown"

var _pack: MapPack


func before() -> void:
	var dir := PackLocator.find_pack(PACK_ID)
	assert_str(dir).override_failure_message("pack not found; searched %s" % [PackLocator.search_dirs()]).is_not_empty()
	_pack = MapPack.new()
	assert_bool(_pack.load(dir)).is_true()


func test_chunk_count_matches_terrain_index() -> void:
	assert_int(_pack.chunk_coords().size()).is_equal(_pack.terrain_index["chunks"].size())
	assert_int(_pack.chunk_coords().size()).is_greater(100)


func test_terrain_decodes_close_to_road_ground() -> void:
	var entry: Dictionary = _pack.terrain_index["chunks"][0]
	var heights := TerrainBuilder.load_chunk(_pack.pack_dir, _pack.terrain_index, entry)
	assert_object(heights).is_not_null()
	assert_int(heights.heights.size()).is_equal(heights.samples * heights.samples)
	var checked := 0
	for nid in _pack.graph.sorted_node_ids():
		var n: RoadGraph.RoadNode = _pack.graph.nodes[nid]
		if RoadGeometry.chunk_of(n.position) != Vector2i(heights.cx, heights.cz):
			continue
		var has_bridge := false
		for eid in _pack.graph.incident(nid):
			var e: RoadGraph.RoadEdge = _pack.graph.edges[eid]
			has_bridge = has_bridge or e.bridge or e.tunnel
		if has_bridge:
			continue
		var h := heights.sample(n.position.x, n.position.z)
		assert_float(absf(h - n.position.y)).override_failure_message("node %s road y %.2f terrain %.2f" % [nid, n.position.y, h]).is_less(0.5)
		checked += 1
		if checked >= 5:
			break


func test_terrain_lod_vertex_counts() -> void:
	var entry: Dictionary = _pack.terrain_index["chunks"][0]
	var heights := TerrainBuilder.load_chunk(_pack.pack_dir, _pack.terrain_index, entry)
	for lod in range(3):
		var mesh := TerrainBuilder.build_mesh(heights, lod)
		var step: int = TerrainBuilder.LOD_STEPS[lod]
		var n: int = (heights.samples - 1) / step + 1
		assert_int(mesh.surface_get_array_len(0)).is_equal(n * n)


func test_build_chunk_has_collision_and_lods() -> void:
	var road_result := RoadMeshBuilder.build(_pack.graph, _pack.junctions)
	var coord: Vector2i = road_result.roads.keys()[0]
	var entry: Dictionary = {}
	for e in _pack.terrain_index["chunks"]:
		if int(e["cx"]) == coord.x and int(e["cz"]) == coord.y:
			entry = e
	var heights := TerrainBuilder.load_chunk(_pack.pack_dir, _pack.terrain_index, entry)
	var chunk: Node3D = auto_free(_pack.build_chunk(coord, heights, road_result, true))
	assert_object(chunk.get_node_or_null("roads_lod0")).is_not_null()
	assert_object(chunk.get_node_or_null("terrain_lod0")).is_not_null()
	assert_object(chunk.get_node_or_null("terrain_lod2")).is_not_null()
	var body: StaticBody3D = chunk.get_node("collision")
	assert_int(body.get_child_count()).is_greater_equal(2)
	for shape in body.get_children():
		assert_object((shape as CollisionShape3D).shape).is_instanceof(ConcavePolygonShape3D)
	var lod0: MeshInstance3D = chunk.get_node("terrain_lod0")
	var lod1: MeshInstance3D = chunk.get_node("terrain_lod1")
	assert_float(lod0.visibility_range_end).is_equal(lod1.visibility_range_begin)


func test_glb_round_trip_keeps_meshes() -> void:
	var road_result := RoadMeshBuilder.build(_pack.graph, _pack.junctions)
	var coord: Vector2i = road_result.roads.keys()[0]
	var entry: Dictionary = {}
	for e in _pack.terrain_index["chunks"]:
		if int(e["cx"]) == coord.x and int(e["cz"]) == coord.y:
			entry = e
	var heights := TerrainBuilder.load_chunk(_pack.pack_dir, _pack.terrain_index, entry)
	var chunk: Node3D = auto_free(_pack.build_chunk(coord, heights, road_result, false))
	var path := ProjectSettings.globalize_path("user://test_chunk_%d.glb" % Time.get_ticks_usec())
	assert_int(GlbChunks.export_chunk(chunk, path)).is_equal(OK)
	var back: Node3D = auto_free(GlbChunks.import_chunk(path, _pack.road_material, _pack.terrain_material, true))
	assert_object(back).is_not_null()
	for role in ["roads_lod0", "terrain_lod0", "terrain_lod1", "terrain_lod2"]:
		var a: MeshInstance3D = chunk.get_node(role)
		var b: MeshInstance3D = back.get_node_or_null(role)
		assert_object(b).override_failure_message("missing %s after import" % role).is_not_null()
		# Triangles, not vertices: glTF import drops vertices no triangle uses (a terrain hole
		# for a garage ramp leaves a few).
		assert_int(_triangles(b.mesh)).override_failure_message("%s triangles" % role).is_equal(_triangles(a.mesh))
	assert_object(back.get_node_or_null("collision")).is_not_null()
	DirAccess.remove_absolute(path)


static func _triangles(m: Mesh) -> int:
	var n: int = m.surface_get_array_index_len(0)
	return (n if n > 0 else m.surface_get_array_len(0)) / 3


func test_spawn_is_on_the_highway() -> void:
	var t := _pack.spawn_transform()
	var best := INF
	for eid in _pack.graph.sorted_edge_ids():
		var e: RoadGraph.RoadEdge = _pack.graph.edges[eid]
		if e.road_class != "motorway":
			continue
		for i in range(e.polyline.size() - 1):
			var a := Vector2(e.polyline[i].x, e.polyline[i].z)
			var b := Vector2(e.polyline[i + 1].x, e.polyline[i + 1].z)
			var q := Geometry2D.get_closest_point_to_segment(Vector2(t.origin.x, t.origin.z), a, b)
			best = minf(best, q.distance_to(Vector2(t.origin.x, t.origin.z)))
	assert_float(best).is_less(8.0)  # lane offset from the centreline


func test_nearest_edge_finds_the_spawn_road() -> void:
	var t := _pack.spawn_transform()
	var hit := _pack.graph.nearest_edge(t.origin, 30.0)
	assert_bool(hit.is_empty()).is_false()
	var e: RoadGraph.RoadEdge = hit["edge"]
	assert_str(e.road_class).is_equal("motorway")
	assert_float(hit["distance"]).is_less(8.0)  # lane offset from the centreline
	assert_bool(_pack.graph.nearest_edge(Vector3(99999, 0, 99999), 30.0).is_empty()).is_true()


func test_stale_chunks_are_detected() -> void:
	var tmp := ProjectSettings.globalize_path("user://stale_pack_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp.path_join("chunks"))
	var f := FileAccess.open(tmp.path_join("road_graph.v0.json"), FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	assert_bool(GlbChunks.chunks_are_current(tmp)).is_false()
	var m := FileAccess.open(tmp.path_join("chunks").path_join(GlbChunks.BUILD_MANIFEST), FileAccess.WRITE)
	m.store_string(JSON.stringify({"inputs_hash": GlbChunks.inputs_hash(tmp)}))
	m.close()
	assert_bool(GlbChunks.chunks_are_current(tmp)).is_true()
	f = FileAccess.open(tmp.path_join("road_graph.v0.json"), FileAccess.WRITE)
	f.store_string("{\"changed\": true}")
	f.close()
	assert_bool(GlbChunks.chunks_are_current(tmp)).is_false()


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_chunks_go_stale_when_any_pack_file_changes() -> void:
	# Review fix: the cache key covered five files, so a bridges-only (or terrain image) change
	# loaded the old chunks as current.
	var tmp := ProjectSettings.globalize_path("user://stale_inputs_%d" % Time.get_ticks_usec())
	_write(tmp.path_join("road_graph.v0.json"), "{}")
	_write(tmp.path_join("bridges.v0.json"), "{\"bridges\": []}")
	_write(tmp.path_join("terrain").path_join("chunk_0_0.png"), "png")
	_write(tmp.path_join("chunks").path_join(GlbChunks.BUILD_MANIFEST), JSON.stringify({"inputs_hash": GlbChunks.inputs_hash(tmp)}))
	assert_bool(GlbChunks.chunks_are_current(tmp)).is_true()
	_write(tmp.path_join("chunks").path_join("chunk_0_0.glb"), "glb")  # the cache itself: no effect
	assert_bool(GlbChunks.chunks_are_current(tmp)).is_true()
	_write(tmp.path_join("bridges.v0.json"), "{\"bridges\": [1]}")
	assert_bool(GlbChunks.chunks_are_current(tmp)).is_false()
	_write(tmp.path_join("chunks").path_join(GlbChunks.BUILD_MANIFEST), JSON.stringify({"inputs_hash": GlbChunks.inputs_hash(tmp)}))
	_write(tmp.path_join("terrain").path_join("chunk_0_0.png"), "PNG")
	assert_bool(GlbChunks.chunks_are_current(tmp)).is_false()


func test_chunks_stay_current_when_only_non_geometry_files_change() -> void:
	# Review fix: a regenerated validation report or an ad edit rebuilt every chunk.
	var tmp := ProjectSettings.globalize_path("user://stale_report_%d" % Time.get_ticks_usec())
	_write(tmp.path_join("road_graph.v0.json"), "{}")
	_write(tmp.path_join("pack.json"), "{\"id\": \"t\"}")
	_write(tmp.path_join("validation_report.json"), "{\"runs\": 1}")
	_write(tmp.path_join("ads.v0.json"), "{\"ads\": []}")
	_write(tmp.path_join("chunks").path_join(GlbChunks.BUILD_MANIFEST), JSON.stringify({"inputs_hash": GlbChunks.inputs_hash(tmp)}))
	assert_bool(GlbChunks.chunks_are_current(tmp)).is_true()
	_write(tmp.path_join("validation_report.json"), "{\"runs\": 2}")
	_write(tmp.path_join("validation_report.md"), "# report")
	_write(tmp.path_join("pack.json"), "{\"id\": \"t\", \"attribution\": [\"x\"]}")
	_write(tmp.path_join("ads.v0.json"), "{\"ads\": [1]}")
	assert_bool(GlbChunks.chunks_are_current(tmp)).is_true()
	_write(tmp.path_join("road_graph.v0.json"), "{\"changed\": true}")
	assert_bool(GlbChunks.chunks_are_current(tmp)).is_false()


func test_content_hash_reads_the_bytes_not_just_the_sizes() -> void:
	# Review fix: two regenerated packs with equal file sizes passed the co-op check.
	var base := ProjectSettings.globalize_path("user://content_hash_%d" % Time.get_ticks_usec())
	for side in ["a", "b"]:
		_write(base.path_join(side).path_join("pack.json"), "{\"id\": \"t\"}")
		_write(base.path_join(side).path_join("chunks").path_join("chunk_0_0.glb"), side)
	_write(base.path_join("a").path_join("road_graph.v0.json"), "{\"y\": 1}")
	_write(base.path_join("b").path_join("road_graph.v0.json"), "{\"y\": 2}")
	assert_str(MapPack.content_hash(base.path_join("a"))).is_not_equal(MapPack.content_hash(base.path_join("b")))
	_write(base.path_join("b").path_join("road_graph.v0.json"), "{\"y\": 1}")
	# Same contents; the local GLB caches differ and don't count.
	assert_str(MapPack.content_hash(base.path_join("a"))).is_equal(MapPack.content_hash(base.path_join("b")))


func test_manifest_hash_is_computed_once_per_load() -> void:
	# Review fix: the report form re-hashed every pack file on each open.
	var a := _pack.manifest_summary()
	var b := _pack.manifest_summary()
	assert_str(a["hash"]).is_equal(b["hash"])
	assert_str(a["hash"]).is_equal(MapPack.content_hash(_pack.pack_dir))
	assert_int(_pack.content_hash_runs).is_equal(1)


func test_parking_lots_load_and_build_in_their_chunks() -> void:
	assert_int(_pack.parking_lots.size()).is_greater(600)  # surface and street-side lots
	var stalls := 0
	var with_stalls := 0
	for lot in _pack.parking_lots:
		stalls += lot.stalls.size()
		if not lot.stalls.is_empty():
			with_stalls += 1
	print("parking: %d lots drawn, %d with stalls, %d stalls" % [_pack.parking_lots.size(), with_stalls, stalls])
	assert_int(with_stalls).is_greater(_pack.parking_lots.size() / 2)
	# A chunk with a lot builds its asphalt, markings, props and sign labels.
	var road_result := RoadMeshBuilder.build(_pack.graph, _pack.junctions)
	var built := 0
	for coord: Vector2i in _pack.parking_chunks:
		var entry: Dictionary = {}
		for e in _pack.terrain_index["chunks"]:
			if int(e["cx"]) == coord.x and int(e["cz"]) == coord.y:
				entry = e
		if entry.is_empty():
			continue
		var heights := TerrainBuilder.load_chunk(_pack.pack_dir, _pack.terrain_index, entry)
		var chunk: Node3D = auto_free(_pack.build_chunk(coord, heights, road_result, true))
		assert_object(chunk.get_node_or_null("parking_lod0")).is_not_null()
		assert_object(chunk.get_node_or_null("parking_markings_lod0")).is_not_null()
		built += 1
		if built >= 2:
			break
	assert_int(built).is_equal(2)
