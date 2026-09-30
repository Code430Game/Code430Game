extends GdUnitTestSuite
## Barrier walls: faces point outward, tops up, heights and thickness by kind; the Ottawa pack loads them.


func _barrier(kind: String, height: float, points: Array) -> BarrierBuilder.Barrier:
	var b := BarrierBuilder.Barrier.new()
	b.id = "b0"
	b.kind = kind
	b.height_m = height
	for p in points:
		b.points.append(Vector3(p[0], p[1], p[2]))
	return b


func _front_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (c - a).cross(b - a).normalized()


func test_wall_faces_point_outward_and_top_up() -> void:
	var bars: Array[BarrierBuilder.Barrier] = [_barrier("soundwall", 4.0, [[0, 10, 0], [50, 10, 0]])]
	var tris: RoadMeshBuilder.ChunkTriangles = BarrierBuilder.build(bars)[Vector2i(0, 0)]
	# 3 faces (left, right, top) + 2 caps, 2 triangles each = 10
	assert_int(tris.vertices.size() / 3).is_equal(10)
	var up := 0
	var side := 0
	var max_y := -INF
	var min_y := INF
	for t in range(0, tris.vertices.size(), 3):
		var a := tris.vertices[t]
		var b := tris.vertices[t + 1]
		var c := tris.vertices[t + 2]
		var n := _front_normal(a, b, c)
		var mid := (a + b + c) / 3.0
		for v in [a, b, c]:
			max_y = maxf(max_y, v.y)
			min_y = minf(min_y, v.y)
		if n.y > 0.9:
			up += 1
		elif absf(n.z) > 0.9:
			side += 1
			assert_float(n.z * mid.z).is_greater(0.0)  # +z face points +z, -z face points -z
	assert_int(up).is_equal(2)
	assert_int(side).is_equal(4)
	assert_float(max_y).is_equal_approx(14.0, 1e-4)
	assert_float(min_y).is_equal_approx(10.0 - BarrierBuilder.EMBED_M, 1e-4)
	var thickness: float = BarrierBuilder.STYLE["soundwall"]["thickness"]
	var zs := {}
	for v in tris.vertices:
		zs[snappedf(absf(v.z), 0.001)] = true
	assert_bool(zs.has(snappedf(thickness * 0.5, 0.001))).is_true()


func test_curb_is_low_and_split_across_chunks() -> void:
	var bars: Array[BarrierBuilder.Barrier] = [_barrier("curb", 0.12, [[200, 5, 0], [300, 5, 0]])]
	var buckets := BarrierBuilder.build(bars)
	assert_bool(buckets.has(Vector2i(0, 0))).is_true()
	assert_bool(buckets.has(Vector2i(1, 0))).is_true()
	var max_y := -INF
	for v in buckets[Vector2i(1, 0)].vertices:
		max_y = maxf(max_y, v.y)
	assert_float(max_y).is_equal_approx(5.12, 1e-4)


func test_ottawa_pack_loads_barriers() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack("code430.ottawa-centretown"))).is_true()
	assert_int(pack.barriers.size()).is_greater(1000)
	var kinds := {}
	for b in pack.barriers:
		kinds[b.kind] = true
	assert_array(kinds.keys()).contains(["parapet", "median", "guardrail", "soundwall", "curb"])
	assert_int(pack.barrier_chunks.size()).is_greater(50)
