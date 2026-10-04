extends GdUnitTestSuite
## TrimSheet: deterministic, cells where the UVs say, blank cell white.


func _sample(img: Image, cell: String, u: float, v: float) -> Color:
	var r := TrimSheet.uv_rect(cell)
	var p := (r.position + r.size * Vector2(u, v)) * TrimSheet.SIZE
	return img.get_pixel(int(p.x), int(p.y))


func test_atlas_is_the_same_every_build() -> void:
	var a := TrimSheet.build_image()
	var b := TrimSheet.build_image()
	assert_int(a.get_width()).is_equal(256)
	assert_bool(a.get_data() == b.get_data()).is_true()


func test_cells_hold_their_details() -> void:
	var img := TrimSheet.build_image()
	assert_that(_sample(img, "blank", 0.5, 0.5)).is_equal(Color.WHITE)  # body stays the instance colour
	assert_float(_sample(img, "dark", 0.5, 0.5).v).is_less(0.15)
	assert_float(_sample(img, "lens", 0.5, 0.5).v).is_greater(_sample(img, "lens", 0.02, 0.02).v)
	var a := _sample(img, "check", 0.1, 0.1)
	var b := _sample(img, "check", 0.25, 0.1)
	assert_float(absf(a.v - b.v)).is_greater(0.5)  # alternating squares
	assert_float(_sample(img, "tint", 0.5, 0.5).b).is_greater(_sample(img, "tint", 0.5, 0.5).r)


func test_uv_rects_stay_inside_their_cells() -> void:
	var seen := {}
	for cell: String in TrimSheet.CELLS:
		var r := TrimSheet.uv_rect(cell)
		assert_float(r.position.x).is_greater_equal(0.0)
		assert_float(r.end.x).is_less_equal(1.0)
		var key := Vector2i(int(r.position.x * 8), int(r.position.y * 8))
		assert_bool(seen.has(key)).override_failure_message("%s overlaps another cell" % cell).is_false()
		seen[key] = true
