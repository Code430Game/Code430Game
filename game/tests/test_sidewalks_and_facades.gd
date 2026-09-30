extends GdUnitTestSuite
## Sidewalk ribbons and facade UVs/treatments.


func _way(kind: String, width: float, points: Array) -> RoadGraph.PedestrianWay:
	var w := RoadGraph.PedestrianWay.new()
	w.id = "p1"
	w.kind = kind
	w.width_m = width
	w.road_class = "footway"
	for p in points:
		w.polyline.append(Vector3(p[0], p[1], p[2]))
	return w


func test_sidewalk_ribbon_faces_up_and_uses_width() -> void:
	var ways: Array[RoadGraph.PedestrianWay] = [_way("sidewalk", 2.0, [[0, 10.12, 0], [50, 10.12, 0]])]
	var buckets := SidewalkBuilder.build(ways)
	var tris: RoadMeshBuilder.ChunkTriangles = buckets[Vector2i(0, 0)]
	assert_int(tris.vertices.size() / 3).is_equal(2)
	var zs := {}
	for v in tris.vertices:
		zs[snappedf(absf(v.z), 0.01)] = true
		assert_float(v.y).is_equal_approx(10.12 + SidewalkBuilder.SURFACE_LIFT_M, 1e-4)
	assert_bool(zs.has(1.0)).is_true()
	var a := tris.vertices[0]
	var n := (tris.vertices[2] - a).cross(tris.vertices[1] - a).normalized()
	assert_float(n.y).is_greater(0.99)


func test_crossing_sits_at_road_level() -> void:
	var ways: Array[RoadGraph.PedestrianWay] = [_way("crossing", 3.0, [[0, 10.12, 0], [10, 10.12, 0]])]
	var tris: RoadMeshBuilder.ChunkTriangles = SidewalkBuilder.build(ways)[Vector2i(0, 0)]
	assert_float(tris.vertices[0].y).is_equal_approx(10.12 + SidewalkBuilder.SURFACE_LIFT_M - SidewalkBuilder.CROSSING_DROP_M, 1e-4)


func test_treatment_rules() -> void:
	assert_int(BuildingBuilder.treatment_for("house", 6.4)).is_equal(BuildingBuilder.TREATMENT_PUNCHED)
	assert_int(BuildingBuilder.treatment_for("office", 30.0)).is_equal(BuildingBuilder.TREATMENT_GLASS)
	assert_int(BuildingBuilder.treatment_for("office", 9.0)).is_equal(BuildingBuilder.TREATMENT_PUNCHED)
	assert_int(BuildingBuilder.treatment_for("church", 12.8)).is_equal(BuildingBuilder.TREATMENT_STONE)
	assert_int(BuildingBuilder.treatment_for("garage", 3.2)).is_equal(BuildingBuilder.TREATMENT_PLAIN)
	assert_int(BuildingBuilder.treatment_for("apartments", 45.0)).is_equal(BuildingBuilder.TREATMENT_GLASS)
	assert_float(BuildingBuilder.seed_for("w1.0")).is_between(0.0, 1.0)
	assert_float(BuildingBuilder.seed_for("w1.0")).is_not_equal(BuildingBuilder.seed_for("w2.0"))


func test_wall_uvs_are_metres() -> void:
	var b := BuildingBuilder.Building.new()
	b.id = "w9.0"
	b.kind = "house"
	b.height_m = 8.0
	b.ground_y = 50.0
	var ring := PackedVector2Array([Vector2(0, 0), Vector2(12, 0), Vector2(12, 5), Vector2(0, 5)])
	b.rings.append(ring)
	b.roof_vertices = ring
	b.roof_triangles = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var tris: RoadMeshBuilder.ChunkTriangles = BuildingBuilder.build([b])["lod0"][Vector2i(0, 0)]
	assert_int(tris.uvs.size()).is_equal(tris.vertices.size())
	var max_u := 0.0
	var min_v := INF
	var max_v := -INF
	var walls := 0
	for i in range(tris.vertices.size()):
		if tris.uv2s[i].x >= 0.0:
			walls += 1
			max_u = maxf(max_u, tris.uvs[i].x)
			min_v = minf(min_v, tris.uvs[i].y)
			max_v = maxf(max_v, tris.uvs[i].y)
			assert_float(tris.uv2s[i].x).is_equal(float(BuildingBuilder.TREATMENT_PUNCHED))
	assert_int(walls).is_equal(24)
	assert_float(max_u).is_equal_approx(12.0 + 5.0 + 12.0 + 5.0, 1e-4)  # perimeter, cumulative along the ring
	assert_float(min_v).is_equal_approx(-BuildingBuilder.WALL_EMBED_M, 1e-4)
	assert_float(max_v).is_equal_approx(8.0, 1e-4)
	var mesh := tris.to_mesh()
	assert_int(mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2).is_not_equal(0)


func test_ottawa_pack_has_sidewalks() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack("code430.ottawa-centretown"))).is_true()
	assert_int(pack.graph.pedestrian.size()).is_greater(5000)
	assert_int(pack.sidewalk_chunks.size()).is_greater(100)
