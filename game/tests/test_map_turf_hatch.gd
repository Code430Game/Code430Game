extends GdUnitTestSuite
## A turf's hatching stays inside the turf (human, Deck 2026-10-21: drove through the striped
## area and met no gang; the stripes were drawn outside the ring, the turf left plain).

const RING := [Vector2(100, 100), Vector2(300, 100), Vector2(300, 250), Vector2(100, 250)]


func _ring() -> PackedVector2Array:
	return PackedVector2Array(RING)


func test_every_stripe_lies_inside_the_turf() -> void:
	var segs := MapRenderer.turf_hatch(_ring(), 6.0)
	assert_int(segs.size()).is_greater(20)
	var inside := Rect2(Vector2(99.9, 99.9), Vector2(200.2, 150.2))
	for seg in segs:
		for p in seg:
			assert_bool(inside.has_point(p)).override_failure_message("stripe point %s outside the turf" % p).is_true()


func test_the_stripes_cover_the_turf() -> void:
	var segs := MapRenderer.turf_hatch(_ring(), 6.0)
	var covered := 0.0
	for seg in segs:
		covered += seg[0].distance_to(seg[seg.size() - 1])
	# 45 degree lines 6 px apart over a 200 x 150 rectangle: about area * sqrt(2) / 6.
	assert_float(covered).is_greater(200.0 * 150.0 * 1.414 / 6.0 * 0.9)


func test_a_ring_of_two_points_has_no_hatching() -> void:
	assert_int(MapRenderer.turf_hatch(PackedVector2Array([Vector2.ZERO, Vector2.ONE]), 6.0).size()).is_equal(0)
