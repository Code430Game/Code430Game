extends GdUnitTestSuite
## Sidewalk slab joints: ribbons carry metres along and across in UV and (width, slab) in UV2;
## the shader draws a joint every slab length and down the middle of wide ribbons.


func _way(kind: String, length: float, width: float) -> RoadGraph.PedestrianWay:
	var w := RoadGraph.PedestrianWay.new()
	w.id = "p1"
	w.kind = kind
	w.width_m = width
	w.polyline = PackedVector3Array([Vector3(10, 70, 10), Vector3(10 + length * 0.5, 70, 10), Vector3(10 + length, 70, 10)])
	return w


func _tris(kind: String, length: float, width: float) -> RoadMeshBuilder.ChunkTriangles:
	var ways: Array[RoadGraph.PedestrianWay] = [_way(kind, length, width)]
	var buckets := SidewalkBuilder.build(ways)
	assert_int(buckets.size()).is_equal(1)
	return buckets.values()[0]


## Joint lines crossed walking `length` metres along a ribbon, the way the shader draws them.
func _joints(slab: float, length: float) -> int:
	return int(floor(length / slab))


func test_sidewalks_carry_along_and_across_uvs() -> void:
	var t := _tris("sidewalk", 15.0, 2.0)
	assert_int(t.uvs.size()).is_equal(t.vertices.size())
	var max_along := 0.0
	for i in range(t.vertices.size()):
		var v := t.vertices[i]
		var uv := t.uvs[i]
		assert_float(uv.x).is_equal_approx(v.x - 10.0, 0.01)  # metres along the way
		assert_float(absf(uv.y)).is_equal_approx(1.0, 0.01)  # half the width either side
		max_along = maxf(max_along, uv.x)
		assert_that(t.uv2s[i]).is_equal(Vector2(2.0, SidewalkBuilder.SLAB_M["sidewalk"]))
	assert_float(max_along).is_equal_approx(15.0, 0.01)


func test_fifteen_metres_of_sidewalk_cross_ten_joints() -> void:
	assert_int(_joints(float(SidewalkBuilder.SLAB_M["sidewalk"]), 15.0)).is_equal(10)
	assert_float(float(SidewalkBuilder.SLAB_M["path"])).is_equal(2.0)


func test_crossings_and_cycle_lanes_get_no_joints() -> void:
	for kind: String in ["crossing", "cycleway", "steps"]:
		var t := _tris(kind, 10.0, 3.0)
		for uv2 in t.uv2s:
			assert_float(uv2.y).override_failure_message("%s has joints" % kind).is_equal(0.0)


func test_the_shader_draws_joints_only_where_asked() -> void:
	var code := FileAccess.get_file_as_string("res://world/roads/ground_detail.gdshader")
	assert_bool(code.contains("fract(UV.x / slab)")).is_true()
	assert_bool(code.contains("UV2.x > 3.0")).is_true()  # the joint down the middle of wide ribbons
	var walk := SidewalkBuilder.material() as ShaderMaterial
	var road := MapPack._road_material() as ShaderMaterial
	assert_bool(walk.get_shader_parameter("joints") == true).is_true()
	assert_bool(road.get_shader_parameter("joints") == true).is_false()  # unset: the shader default (off)
