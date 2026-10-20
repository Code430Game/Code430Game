extends GdUnitTestSuite
## Yards: lawns draped on the terrain, the path from the door, hedges with a gap for the path,
## fences on the ground, chunk bucketing, and the proving ground's yards built in the pack.


const YARD := {
	"house": "w1.0",
	"front": [[[[0, 2], [10, 2], [10, 10], [0, 10]]]],
	"back": [[[[0, 20], [10, 20], [10, 40], [0, 40]]]],
	"side": [],
	"path": [[5, 10], [5, 2]],
	"frontage": [[[0, 2], [10, 2]]],
}


func _sloped_heights() -> TerrainBuilder.ChunkHeights:
	var h := TerrainBuilder.ChunkHeights.new()
	h.cx = 0
	h.cz = 0
	h.samples = 65
	h.resolution_m = 4.0
	for r in range(65):
		for c in range(65):
			h.heights.append(70.0 + c * 4.0 * 0.05)  # rises 5 cm per metre eastward
	return h


func _loaded(yard: Dictionary, fences: Array) -> Dictionary:
	var yards: Array[YardBuilder.Yard] = [YardBuilder.yard_from_dict(yard)]
	var lines: Array[PackedVector2Array] = []
	for f: Array in fences:
		lines.append(PackedVector2Array(f))
	return {"yards": yards, "fences": lines}


func test_lawns_follow_the_terrain_and_cover_the_yard() -> void:
	var heights := _sloped_heights()
	var buckets := YardBuilder.by_chunk(_loaded(YARD, []), 256.0)
	var built := YardBuilder.build_chunk(buckets[Vector2i(0, 0)], Vector2i(0, 0), heights, 256.0)
	var lawns: RoadMeshBuilder.ChunkTriangles = built["lawns"]
	var area := 0.0
	for t in range(0, lawns.vertices.size(), 3):
		var a := lawns.vertices[t]
		var b := lawns.vertices[t + 1]
		var c := lawns.vertices[t + 2]
		var n := (b - a).cross(c - a)
		assert_float(n.y).is_less(0.0)  # faces up
		if lawns.colors[t] == YardBuilder.PATH:
			continue
		for v in [a, b, c]:
			assert_float(v.y).is_equal_approx(heights.sample(v.x, v.z) + YardBuilder.LAWN_LIFT_M, 0.001)
		area += absf(n.y) * 0.5
	assert_float(area).is_equal_approx(10.0 * 8.0 + 10.0 * 20.0, 0.5)
	assert_bool(lawns.colors.has(YardBuilder.PATH)).is_true()


func test_hedges_leave_a_gap_for_the_path() -> void:
	var segs := YardBuilder.hedge_segments(PackedVector2Array([Vector2(0, 2), Vector2(10, 2)]), PackedVector2Array([Vector2(5, 10), Vector2(5, 2)]))
	assert_int(segs.size()).is_equal(2)
	assert_float((segs[0][1] as Vector2).x).is_equal_approx(5.0 - YardBuilder.HEDGE_GAP_M, 0.01)
	assert_float((segs[1][0] as Vector2).x).is_equal_approx(5.0 + YardBuilder.HEDGE_GAP_M, 0.01)
	# A frontage the path does not cross is one hedge.
	assert_int(YardBuilder.hedge_segments(PackedVector2Array([Vector2(0, 2), Vector2(10, 2)]), PackedVector2Array()).size()).is_equal(1)


func test_fences_stand_on_the_ground_with_posts_and_panels() -> void:
	var heights := _sloped_heights()
	var buckets := YardBuilder.by_chunk(_loaded(YARD, [[Vector2(10, 20), Vector2(10, 40)], [Vector2(0, 40), Vector2(20, 40)]]), 256.0)
	var built := YardBuilder.build_chunk(buckets[Vector2i(0, 0)], Vector2i(0, 0), heights, 256.0)
	var props: RoadMeshBuilder.ChunkTriangles = built["props"]
	assert_bool(props.colors.has(YardBuilder.FENCE)).is_true()
	assert_bool(props.colors.has(YardBuilder.FENCE_POST)).is_true()
	var lo := INF
	var hi := -INF
	for i in range(props.vertices.size()):
		if props.colors[i] != YardBuilder.FENCE:
			continue
		var v := props.vertices[i]
		var g := heights.sample(v.x, v.z)
		lo = minf(lo, v.y - g)
		hi = maxf(hi, v.y - g)
	assert_float(lo).is_less_equal(0.0)  # no gap under a panel, on the slope too
	assert_float(hi).is_between(YardBuilder.FENCE_H_M - 0.3, YardBuilder.FENCE_H_M + 0.3)


func test_yards_are_bucketed_into_every_chunk_they_touch_and_fences_by_their_middle() -> void:
	var y := YARD.duplicate(true)
	y["back"] = [[[[250, 20], [262, 20], [262, 40], [250, 40]]]]
	var buckets := YardBuilder.by_chunk(_loaded(y, [[Vector2(250, 30), Vector2(270, 30)]]), 256.0)
	assert_bool(buckets.has(Vector2i(0, 0)) and buckets.has(Vector2i(1, 0))).is_true()
	assert_int((buckets[Vector2i(1, 0)]["fences"] as Array).size()).is_equal(1)  # middle at x = 260
	assert_int((buckets[Vector2i(0, 0)]["fences"] as Array).size()).is_equal(0)


func test_the_proving_ground_has_yards_and_fences_near_its_houses() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../packs/proving-ground").simplify_path()
	var loaded := YardBuilder.load_yards(dir)
	assert_int((loaded["yards"] as Array).size()).is_greater(1000)
	assert_int((loaded["fences"] as Array).size()).is_greater(1000)
	var hedges := 0
	for y: YardBuilder.Yard in loaded["yards"]:
		if y.has_hedge():
			hedges += 1
	var share := float(hedges) / (loaded["yards"] as Array).size()
	assert_float(share).is_between(YardBuilder.HEDGE_SHARE - 0.1, YardBuilder.HEDGE_SHARE + 0.1)


func test_every_face_of_a_hedge_strip_faces_outward() -> void:
	var heights := _sloped_heights()
	for dir: Vector2 in [Vector2(10, 0), Vector2(0, 10), Vector2(-7, 7), Vector2(7, 3)]:
		var tris := RoadMeshBuilder.ChunkTriangles.new()
		var a := Vector2(50, 50)
		ParkingLotBuilder._add_strip(tris, a, a + dir, YardBuilder.HEDGE_W_M, heights, 0.0, YardBuilder.HEDGE_H_M, YardBuilder.HEDGE)
		var centre := Vector3.ZERO
		for v in tris.vertices:
			centre += v
		centre /= tris.vertices.size()
		for t in range(0, tris.vertices.size(), 3):
			var p := tris.vertices[t]
			var q := tris.vertices[t + 1]
			var r := tris.vertices[t + 2]
			var front := -(q - p).cross(r - p)  # Godot: the emitted cross product points away from the viewer
			assert_float(front.dot((p + q + r) / 3.0 - centre)).is_greater(0.0)
