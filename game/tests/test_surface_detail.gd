extends GdUnitTestSuite
## SurfaceDetail: deterministic, centred on mid-grey, seamless; ground materials use it.


func _mean(img: Image) -> float:
	var data := img.get_data()
	var sum := 0
	for b in data:
		sum += b
	return float(sum) / data.size() / 255.0


func test_the_same_pixels_every_build() -> void:
	for kind: String in SurfaceDetail.KINDS:
		var a := SurfaceDetail.build_image(kind, 128)
		var b := SurfaceDetail.build_image(kind, 128)
		assert_bool(a.get_data() == b.get_data()).override_failure_message("%s differs between builds" % kind).is_true()


func test_detail_is_centred_on_mid_grey_and_varies() -> void:
	for kind: String in SurfaceDetail.KINDS:
		var img := SurfaceDetail.build_image(kind, 256)
		assert_float(_mean(img)).override_failure_message("%s mean %.3f" % [kind, _mean(img)]).is_between(0.45, 0.55)
		var lo := 1.0
		var hi := 0.0
		for y in range(0, 256, 8):
			for x in range(0, 256, 8):
				var v := img.get_pixel(x, y).r
				lo = minf(lo, v)
				hi = maxf(hi, v)
		assert_float(hi - lo).is_greater(0.05)  # there is grain to see


func test_textures_tile_without_a_seam() -> void:
	var img := SurfaceDetail.build_image("asphalt", 256)
	var seam := 0.0
	var inside := 0.0
	for y in range(256):
		seam += absf(img.get_pixel(255, y).r - img.get_pixel(0, y).r)
		inside += absf(img.get_pixel(128, y).r - img.get_pixel(129, y).r)
	assert_float(seam).is_less(inside * 3.0 + 2.0)  # wrapping costs about what a step inside costs


func test_ground_materials_sample_the_detail() -> void:
	var road := MapPack._road_material() as ShaderMaterial
	var walk := SidewalkBuilder.material() as ShaderMaterial
	var paint := MarkingBuilder.material() as ShaderMaterial
	for m: ShaderMaterial in [road, walk, paint]:
		assert_object(m).is_not_null()
		assert_object(m.get_shader_parameter("detail")).is_not_null()
	assert_float(float(walk.get_shader_parameter("tile_m"))).is_less(float(road.get_shader_parameter("tile_m")))
	assert_float(float(paint.get_shader_parameter("emission_energy"))).is_greater(0.0)
