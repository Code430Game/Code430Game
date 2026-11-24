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


## add-retaining-walls: a wall's top follows `tops_m`, one height per point, interpolated
## along the line and at the chunk boundary where the wall is split, so the halves meet.
func test_a_retaining_wall_rises_by_its_tops_and_meets_itself_at_the_chunk_boundary() -> void:
	var wall := _barrier("wall", 4.0, [[200, 10, 0], [300, 10, 0]])
	wall.tops_m = PackedFloat32Array([2.0, 4.0])
	var buckets := BarrierBuilder.build([wall] as Array[BarrierBuilder.Barrier])
	assert_bool(buckets.has(Vector2i(0, 0))).is_true()
	assert_bool(buckets.has(Vector2i(1, 0))).is_true()
	var max_west := -INF
	var max_east := -INF
	var top_at_boundary := {}
	for coord in [Vector2i(0, 0), Vector2i(1, 0)]:
		for v in buckets[coord].vertices:
			if coord == Vector2i(0, 0):
				max_west = maxf(max_west, v.y)
			else:
				max_east = maxf(max_east, v.y)
			if absf(v.x - 256.0) < 1e-3 and v.y > 10.5:
				top_at_boundary[snappedf(v.y, 0.001)] = true
	assert_float(max_west).is_equal_approx(10.0 + 2.0 + 2.0 * 0.56, 1e-3)  # the boundary, 56 m along
	assert_float(max_east).is_equal_approx(14.0, 1e-3)
	assert_int(top_at_boundary.size()).is_equal(1)  # one top height at the cut, shared by both halves
	var thickness: float = BarrierBuilder.STYLE["wall"]["thickness"]
	var zs := {}
	for v in buckets[Vector2i(1, 0)].vertices:
		zs[snappedf(absf(v.z), 0.001)] = true
	assert_bool(zs.has(snappedf(thickness * 0.5, 0.001))).is_true()


## A wall with a cap is a solid block: a top in the terrain's colour reaches back over the
## strip where the terrain climbs, on the side the bank is on, and both ends are closed.
func test_a_retaining_wall_with_a_cap_has_a_solid_top_behind_its_face() -> void:
	var plain := _barrier("wall", 3.0, [[10, 10, 0], [30, 10, 0]])
	plain.tops_m = PackedFloat32Array([3.0, 3.0])
	var capped := _barrier("wall", 3.0, [[10, 10, 0], [30, 10, 0]])
	capped.tops_m = PackedFloat32Array([3.0, 3.0])
	capped.cap_m = 11.5
	capped.cap_side = -1.0  # heading east, left is north (-z)
	var plain_tris: RoadMeshBuilder.ChunkTriangles = BarrierBuilder.build([plain] as Array[BarrierBuilder.Barrier])[Vector2i(0, 0)]
	var tris: RoadMeshBuilder.ChunkTriangles = BarrierBuilder.build([capped] as Array[BarrierBuilder.Barrier])[Vector2i(0, 0)]
	# The cap (two triangles) and the two closed ends (two each) on top of the plain wall.
	assert_int(tris.vertices.size()).is_equal(plain_tris.vertices.size() + 18)
	var back_z := INF
	var grass := 0
	for i in range(0, tris.vertices.size(), 3):
		var a := tris.vertices[i]
		var b := tris.vertices[i + 1]
		var c := tris.vertices[i + 2]
		for v in [a, b, c]:
			back_z = minf(back_z, v.z)
			assert_float(v.z).is_less_equal(BarrierBuilder.STYLE["wall"]["thickness"] * 0.5 + 1e-4)  # nothing in front of the face
		if tris.colors[i].is_equal_approx(TerrainBuilder.TERRAIN_COLOR):
			grass += 1
			assert_float((c - a).cross(b - a).normalized().y).is_greater(0.9)  # the top faces up
			for v in [a, b, c]:
				# At the wall's top by the face, CAP_SINK_M lower at the back edge.
				assert_float(v.y).is_equal_approx(13.0 if v.z > -1.0 else 13.0 - BarrierBuilder.CAP_SINK_M, 1e-4)
	assert_float(back_z).is_equal_approx(-11.5, 1e-4)
	assert_int(grass).is_equal(2)


func test_load_walls_reads_the_side_and_the_cap() -> void:
	var dir := "user://test_wall_caps_%d" % randi()
	DirAccess.make_dir_recursive_absolute(dir)
	var walls := {
		"schema_version": 0,
		"units": "m",
		"walls": [
			{"id": "w:a:l0", "edge_id": "a", "height_m": 3.0, "side": "left", "cap_m": 11.5, "points": [[0, 1, 0], [10, 1, 0]], "tops_m": [3.0, 2.0]},
			{"id": "w:a:r0", "edge_id": "a", "height_m": 3.0, "side": "right", "cap_m": 11.5, "points": [[0, 1, 5], [10, 1, 5]], "tops_m": [3.0, 2.0]},
			{"id": "w:b:l0", "edge_id": "b", "height_m": 3.0, "points": [[0, 1, 9], [10, 1, 9]], "tops_m": [3.0, 2.0]},
		],
	}
	var f := FileAccess.open(dir.path_join(BarrierBuilder.WALLS_FILE), FileAccess.WRITE)
	f.store_string(JSON.stringify(walls))
	f.close()
	var loaded := BarrierBuilder.load_walls(dir)
	assert_int(loaded.size()).is_equal(3)
	assert_float(loaded[0].cap_side).is_equal(-1.0)
	assert_float(loaded[0].cap_m).is_equal_approx(11.5, 1e-5)
	assert_float(loaded[1].cap_side).is_equal(1.0)
	assert_float(loaded[2].cap_m).is_equal(0.0)  # an older pack's wall: plain
	DirAccess.remove_absolute(dir.path_join(BarrierBuilder.WALLS_FILE))
	DirAccess.remove_absolute(dir)


func test_split_with_tops_interpolates_the_cut_points_top() -> void:
	var split := BarrierBuilder.split_with_tops(PackedVector3Array([Vector3(250, 0, 10), Vector3(262, 0, 10), Vector3(262, 0, 260)]), PackedFloat32Array([1.0, 3.0, 5.0]))
	var pts: PackedVector3Array = split["points"]
	var tops: PackedFloat32Array = split["tops"]
	assert_int(pts.size()).is_equal(tops.size())
	assert_int(pts.size()).is_equal(5)
	assert_vector(pts[1]).is_equal_approx(Vector3(256, 0, 10), Vector3.ONE * 1e-4)
	assert_float(tops[1]).is_equal_approx(2.0, 1e-4)
	assert_vector(pts[3]).is_equal_approx(Vector3(262, 0, 256), Vector3.ONE * 1e-4)
	assert_float(tops[3]).is_equal_approx(3.0 + 2.0 * (246.0 / 250.0), 1e-4)


func test_load_walls_skips_a_wall_without_a_top_per_point() -> void:
	var dir := "user://test_walls_%d" % randi()
	DirAccess.make_dir_recursive_absolute(dir)
	var walls := {
		"schema_version": 0,
		"units": "m",
		"walls": [
			{"id": "w:a:l0", "edge_id": "a", "height_m": 3.0, "points": [[0, 1, 0], [10, 1, 0]], "tops_m": [3.0, 2.0]},
			{"id": "w:a:r0", "edge_id": "a", "height_m": 3.0, "points": [[0, 1, 5], [10, 1, 5]], "tops_m": [3.0]},
			{"id": "w:b:l0", "edge_id": "b", "height_m": 3.0, "points": [[0, 1, 9], [10, 1, 9]]},
		],
	}
	var f := FileAccess.open(dir.path_join(BarrierBuilder.WALLS_FILE), FileAccess.WRITE)
	f.store_string(JSON.stringify(walls))
	f.close()
	var loaded := BarrierBuilder.load_walls(dir)
	assert_int(loaded.size()).is_equal(1)
	assert_str(loaded[0].id).is_equal("w:a:l0")
	assert_str(loaded[0].kind).is_equal("wall")
	assert_array(loaded[0].tops_m).contains_exactly([3.0, 2.0])
	assert_float(loaded[0].height_m).is_equal(3.0)
	DirAccess.remove_absolute(dir.path_join(BarrierBuilder.WALLS_FILE))
	DirAccess.remove_absolute(dir)


func test_a_pack_without_the_walls_file_has_no_walls() -> void:
	assert_array(BarrierBuilder.load_walls("user://no_such_pack_dir")).is_empty()
	# Other kinds keep one height along the whole line.
	var bars: Array[BarrierBuilder.Barrier] = [_barrier("guardrail", 0.8, [[0, 10, 0], [50, 10, 0]])]
	var max_y := -INF
	for v in BarrierBuilder.build(bars)[Vector2i(0, 0)].vertices:
		max_y = maxf(max_y, v.y)
	assert_float(max_y).is_equal_approx(10.8, 1e-4)
