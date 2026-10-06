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


func _depth_inside(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in range(poly.size()):
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


## update-junction-surfaces (backlog 2026-10-03, "a curb inside a junction where a curved road
## joins"): a curb crossing a junction surface is cut back to its outline, keeping its heights.
func test_a_curb_crossing_a_junction_is_cut_back_to_its_outline() -> void:
	var j := JunctionBuilder.Junction.new()
	j.node_id = "n"
	j.polygon_xz = PackedVector2Array([Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)])
	var curb := BarrierBuilder.Barrier.new()
	curb.id = "b:curb:e:0"
	curb.kind = "curb"
	curb.height_m = 0.12
	curb.edge_id = "e"
	curb.points = PackedVector3Array([Vector3(-20, 0, 0), Vector3(20, 4, 0)])
	var rail := BarrierBuilder.Barrier.new()
	rail.id = "b:guardrail:e:0"
	rail.kind = "guardrail"
	rail.points = curb.points
	var out := BarrierBuilder.clip_curbs([curb, rail] as Array[BarrierBuilder.Barrier], {"n": j})
	var curbs := out.filter(func(b: BarrierBuilder.Barrier) -> bool: return b.kind == "curb")
	assert_int(curbs.size()).is_equal(2)
	for c: BarrierBuilder.Barrier in curbs:
		for p in c.points:
			assert_bool(absf(p.x) < 4.99).override_failure_message("curb point %s inside the junction" % p).is_false()
			assert_float(p.y).is_equal_approx((p.x + 20.0) / 10.0, 1e-3)  # heights kept along the slope
	# Other kinds are not touched.
	assert_int(out.filter(func(b: BarrierBuilder.Barrier) -> bool: return b.kind == "guardrail").size()).is_equal(1)


func test_no_curb_stands_inside_a_junction_on_the_ottawa_pack() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack("code430.ottawa-centretown"))).is_true()
	var cell := 40.0
	var grid := {}  # Vector2i cell -> junctions whose outline touches it
	for k in pack.junctions:
		var j: JunctionBuilder.Junction = pack.junctions[k]
		var seen := {}
		for p in j.polygon_xz:
			var c := Vector2i(floori(p.x / cell), floori(p.y / cell))
			if not seen.has(c):
				seen[c] = true
				if not grid.has(c):
					grid[c] = []
				grid[c].append(j)
	var inside: Array[String] = []
	for b in pack.barriers:
		if b.kind != "curb":
			continue
		for i in range(b.points.size() - 1):
			var mid := (b.points[i] + b.points[i + 1]) * 0.5
			var at := Vector2(mid.x, mid.z)
			for j: JunctionBuilder.Junction in grid.get(Vector2i(floori(at.x / cell), floori(at.y / cell)), []):
				# A curb along the outline itself is where a road runs straight on past the
				# junction: the curb stands on the road's edge, which the outline follows.
				if Geometry2D.is_point_in_polygon(at, j.polygon_xz) and _depth_inside(at, j.polygon_xz) > 0.2:
					inside.append("%s in %s" % [b.id, j.node_id])
					break
	assert_array(inside).override_failure_message("curbs inside junctions: %s" % [inside.slice(0, 8)]).is_empty()
