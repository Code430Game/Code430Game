extends GdUnitTestSuite
## Polyline helpers: chunk splitting, trimming, miters, simplification.


func _line(points: Array) -> PackedVector3Array:
	var pl := PackedVector3Array()
	for p in points:
		pl.append(Vector3(p[0], p[1], p[2]))
	return pl


func test_split_inserts_exact_chunk_boundaries() -> void:
	var pl := _line([[100, 0, 10], [400, 5, 10]])
	var out := RoadGeometry.split_at_chunk_bounds(pl)
	assert_int(out.size()).is_equal(3)
	assert_float(out[1].x).is_equal(256.0)
	assert_float(out[1].y).is_equal_approx(5.0 * (156.0 / 300.0), 1e-5)
	assert_that(RoadGeometry.chunk_of_segment(out[0], out[1])).is_equal(Vector2i(0, 0))
	assert_that(RoadGeometry.chunk_of_segment(out[1], out[2])).is_equal(Vector2i(1, 0))


func test_split_handles_both_axes_and_negative_coords() -> void:
	var pl := _line([[-10, 0, -10], [300, 0, 300]])
	var out := RoadGeometry.split_at_chunk_bounds(pl)
	var xs := []
	var zs := []
	for p in out:
		xs.append(p.x)
		zs.append(p.z)
	assert_bool(xs.has(0.0)).is_true()
	assert_bool(xs.has(256.0)).is_true()
	assert_bool(zs.has(0.0)).is_true()
	assert_bool(zs.has(256.0)).is_true()
	# The diagonal crosses x=0 and z=0 at the same point, likewise x=256 and z=256.
	assert_int(out.size()).is_equal(4)
	assert_that(out[1]).is_equal(Vector3(0, 0, 0))
	assert_that(out[2]).is_equal(Vector3(256, 0, 256))


func test_trim_removes_lengths_from_both_ends() -> void:
	var pl := _line([[0, 0, 0], [50, 0, 0], [100, 0, 0]])
	var out := RoadGeometry.trim(pl, 10.0, 20.0)
	assert_float(out[0].x).is_equal_approx(10.0, 1e-6)
	assert_float(out[out.size() - 1].x).is_equal_approx(80.0, 1e-6)
	assert_float(RoadGeometry.length_xz(out)).is_equal_approx(70.0, 1e-6)


func test_trim_everything_returns_empty() -> void:
	var pl := _line([[0, 0, 0], [10, 0, 0]])
	assert_int(RoadGeometry.trim(pl, 6.0, 6.0).size()).is_equal(0)


func test_miter_normals_straight_and_corner() -> void:
	var straight := _line([[0, 0, 0], [10, 0, 0], [20, 0, 0]])
	var n := RoadGeometry.miter_normals(straight)
	for v in n:
		assert_float(v.length()).is_equal_approx(1.0, 1e-6)
	var corner := _line([[0, 0, 0], [10, 0, 0], [10, 0, 10]])
	var m := RoadGeometry.miter_normals(corner)
	assert_float(m[1].length()).is_equal_approx(sqrt(2.0), 1e-5)


func test_simplify_keeps_ends_and_drops_collinear() -> void:
	var nearly_straight := _line([[0, 0, 0], [10, 0, 0.1], [20, 0, -0.2], [30, 0, 0.1], [40, 0, 0]])
	var out := RoadGeometry.simplify(nearly_straight, 1.0)
	assert_int(out.size()).is_equal(2)
	assert_that(out[0]).is_equal(nearly_straight[0])
	assert_that(out[1]).is_equal(nearly_straight[4])
	var bent := _line([[0, 0, 0], [20, 0, 0], [20, 0, 20]])
	assert_int(RoadGeometry.simplify(bent, 1.0).size()).is_equal(3)


func test_point_at_interpolates_y() -> void:
	var pl := _line([[0, 0, 0], [100, 10, 0]])
	assert_that(RoadGeometry.point_at(pl, 50.0)).is_equal_approx(Vector3(50, 5, 0), Vector3(1e-5, 1e-5, 1e-5))
