extends GdUnitTestSuite
## Water meshes from the Ottawa pack, and the pure map math used by the overview map and minimap.

const PACK_ID := "code430.ottawa-centretown"


func _pack() -> MapPack:
	var dir := PackLocator.find_pack(PACK_ID)
	var pack := MapPack.new()
	assert_bool(pack.load(dir)).is_true()
	return pack


func test_water_polygons_match_the_file() -> void:
	var pack := _pack()
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pack.pack_dir.path_join("water.v0.json")))
	assert_int(pack.water_polygons.size()).is_equal(parsed["polygons"].size())
	assert_int(pack.water_polygons.size()).is_greater(10)
	var names := []
	for w in pack.water_polygons:
		names.append(w.name)
	assert_array(names).contains(["Rideau Canal"])


func test_water_meshes_face_up_and_sit_at_surface_height() -> void:
	var pack := _pack()
	assert_int(pack.water_chunks.size()).is_greater(0)
	var river: WaterBuilder.WaterPolygon = null
	for w in pack.water_polygons:
		if river == null or w.vertices.size() > river.vertices.size():
			river = w
	var total := 0.0
	var count := 0
	var ys := {}
	for chunk in pack.water_chunks:
		var tris: RoadMeshBuilder.ChunkTriangles = pack.water_chunks[chunk]
		for t in range(0, tris.vertices.size(), 3):
			var a := tris.vertices[t]
			var b := tris.vertices[t + 1]
			var c := tris.vertices[t + 2]
			total += (c - a).cross(b - a).normalized().y
			count += 1
			ys[snappedf(a.y, 0.01)] = true
	assert_float(total / count).is_greater(0.99)
	assert_bool(ys.has(snappedf(river.surface_y + WaterBuilder.SURFACE_LIFT_M, 0.01))).is_true()


func test_map_renderer_pixel_mapping_round_trips() -> void:
	var r := MapRenderer.new()
	r.set_bounds(Vector4(-1792.0, -1792.0, 1792.0, 1792.0), 2.0)
	assert_that(r.size_px).is_equal(Vector2i(1792, 1792))
	var px := r.world_to_pixel(0.0, 0.0)
	assert_that(px).is_equal(Vector2(896, 896))
	var back := r.pixel_to_world(r.world_to_pixel(123.4, -567.8))
	assert_float(back.x).is_equal_approx(123.4, 1e-4)
	assert_float(back.y).is_equal_approx(-567.8, 1e-4)
	assert_float(MapRenderer.road_width_px("motorway_link")).is_equal(4.0)
	assert_float(MapRenderer.road_width_px("service")).is_equal(MapRenderer.DEFAULT_ROAD_WIDTH_PX)


func test_minimap_rotation_points_heading_up() -> void:
	# Heading north (-z) needs no rotation; heading east (+x) rotates the map a quarter turn counter-clockwise.
	assert_float(Minimap.map_rotation_for(Vector3(0, 0, -1))).is_equal_approx(0.0, 1e-6)
	assert_float(Minimap.map_rotation_for(Vector3(1, 0, 0))).is_equal_approx(-PI / 2.0, 1e-6)
	assert_float(absf(Minimap.map_rotation_for(Vector3(0, 0, 1)))).is_equal_approx(PI, 1e-6)
