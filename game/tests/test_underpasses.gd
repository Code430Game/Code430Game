extends GdUnitTestSuite
## Tunnel passages built from pedestrian ways with the tunnel profile.


func _tunnel(points: Array, tops: Array) -> RoadGraph.PedestrianWay:
	var w := RoadGraph.PedestrianWay.new()
	w.id = "p1"
	w.kind = "footway"
	w.width_m = 3.0
	w.road_class = "footway"
	w.profile = "tunnel"
	for p in points:
		w.polyline.append(Vector3(p[0], p[1], p[2]))
	for t in tops:
		w.top.append(float(t))
	return w


func test_tunnel_has_floor_walls_ceiling_and_headwalls_within_its_box() -> void:
	var ways: Array[RoadGraph.PedestrianWay] = [_tunnel([[0, 66.6, 0], [20, 66.6, 0]], [69.7, 69.7])]
	var buckets := UnderpassBuilder.build(ways)
	var tris: RoadMeshBuilder.ChunkTriangles = buckets[Vector2i(0, 0)]
	assert_int(tris.vertices.size() / 3).is_greater(20)
	var lo := INF
	var hi := -INF
	var widest := 0.0
	for v in tris.vertices:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
		widest = maxf(widest, absf(v.z))
	assert_float(lo).is_equal_approx(66.6, 0.03)
	assert_float(hi).is_equal_approx(69.7 + UnderpassBuilder.HEADWALL_ABOVE_M, 0.01)
	assert_float(widest).is_equal_approx(1.5 + UnderpassBuilder.ROOF_HALF_M, 0.01)


func test_terrain_holes_cover_the_cut_strip_and_the_mesh_skips_it() -> void:
	var ways: Array[RoadGraph.PedestrianWay] = [_tunnel([[100, 10, 100], [140, 10, 100]], [13.1, 13.1])]
	var holes := UnderpassBuilder.holes_by_chunk(ways)
	assert_bool(holes.has(Vector2i(0, 0))).is_true()
	var strip: Dictionary = holes[Vector2i(0, 0)][0]
	assert_float(strip["half"]).is_equal_approx(1.5 + UnderpassBuilder.HOLE_HALF_M, 0.001)
	var ch := TerrainBuilder.ChunkHeights.new()
	ch.cx = 0
	ch.cz = 0
	ch.samples = 65
	ch.resolution_m = 4.0
	ch.heights.resize(65 * 65)
	ch.heights.fill(10.0)
	var full := TerrainBuilder.build_mesh(ch, 0)
	var cut := TerrainBuilder.build_mesh(ch, 0, holes[Vector2i(0, 0)])
	var n_full: int = full.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()
	var n_cut: int = cut.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()
	assert_int(n_cut).is_less(n_full)
	# 40 m by ~11 m strip on a 4 m grid: roughly 10 x 3 quads gone, never more than 10 x 4
	assert_int((n_full - n_cut) / 6).is_between(20, 44)


func test_plain_and_trench_ways_build_nothing() -> void:
	var w := _tunnel([[0, 1, 0], [5, 1, 0]], [])
	w.profile = "trench"
	var ways: Array[RoadGraph.PedestrianWay] = [w]
	assert_bool(UnderpassBuilder.build(ways).is_empty()).is_true()


func test_loader_reads_profile_and_top() -> void:
	var g := RoadGraph.from_dict({"nodes": [], "edges": [], "pedestrian_ways": [
		{"id": "p1", "polyline": [[0, 1, 0], [5, 1, 0]], "class": "footway", "kind": "footway", "width_m": 2.0, "covered": true, "profile": "tunnel", "top": [4.0, 4.0], "osm_way_id": 1, "name": null},
	]})
	assert_str(g.pedestrian[0].profile).is_equal("tunnel")
	assert_int(g.pedestrian[0].top.size()).is_equal(2)
