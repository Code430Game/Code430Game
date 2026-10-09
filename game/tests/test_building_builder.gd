extends GdUnitTestSuite
## Building extrusion: outward walls, upward roofs, chunk assignment, and the Ottawa pack file.

const PACK_ID := "code430.ottawa-centretown"


func _box(id: String, cx: float, cz: float, half: float, height: float, ground: float, ccw: bool = true) -> BuildingBuilder.Building:
	var b := BuildingBuilder.Building.new()
	b.id = id
	b.kind = "house"
	b.roof_shape = "flat"  # the geometry tests count a flat roof; pitched roofs have their own test
	b.height_m = height
	b.ground_y = ground
	var ring := PackedVector2Array([Vector2(cx - half, cz - half), Vector2(cx + half, cz - half), Vector2(cx + half, cz + half), Vector2(cx - half, cz + half)])
	if not ccw:
		ring.reverse()
	b.rings.append(ring)
	b.roof_vertices = ring
	b.roof_triangles = PackedInt32Array([0, 1, 2, 0, 2, 3])
	return b


func _front_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (c - a).cross(b - a).normalized()


func test_walls_face_outward_and_roof_faces_up() -> void:
	var b := _box("w1.0", 100.0, 100.0, 10.0, 8.0, 50.0)
	var result := BuildingBuilder.build([b])
	var tris: RoadMeshBuilder.ChunkTriangles = result["lod0"][Vector2i(0, 0)]
	assert_int(tris.vertices.size() / 3).is_equal(8 + 2)  # 4 walls x 2 + roof x 2
	var centre := Vector3(100.0, 50.0, 100.0)
	for t in range(0, tris.vertices.size(), 3):
		var a := tris.vertices[t]
		var bb := tris.vertices[t + 1]
		var c := tris.vertices[t + 2]
		var n := _front_normal(a, bb, c)
		var mid := (a + bb + c) / 3.0
		if absf(n.y) > 0.9:
			assert_float(n.y).is_greater(0.9)  # roof up
			assert_float(mid.y).is_equal_approx(58.0, 1e-4)
		else:
			var away := Vector3(mid.x - centre.x, 0.0, mid.z - centre.z).normalized()
			assert_float(n.dot(away)).override_failure_message("wall at %s faces inward" % mid).is_greater(0.9)
			assert_float(minf(a.y, minf(bb.y, c.y))).is_equal_approx(50.0 - BuildingBuilder.WALL_EMBED_M, 1e-4)


func test_lod1_only_for_tall_or_large() -> void:
	var small := _box("w1.0", 10.0, 10.0, 5.0, 6.0, 0.0)
	var tall := _box("w2.0", 40.0, 40.0, 5.0, 20.0, 0.0)
	var large := _box("w3.0", 300.0, 40.0, 12.0, 6.0, 0.0)  # 576 m2 in chunk (1, 0)
	var result := BuildingBuilder.build([small, tall, large])
	assert_int(result["lod0"][Vector2i(0, 0)].vertices.size() / 3).is_equal(20)
	assert_int(result["lod1"][Vector2i(0, 0)].vertices.size() / 3).is_equal(10)
	assert_bool(result["lod1"].has(Vector2i(1, 0))).is_true()


func test_ottawa_pack_loads_buildings() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack(PACK_ID))).is_true()
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pack.pack_dir.path_join("buildings.v0.json")))
	assert_int(pack.buildings.size()).is_equal(parsed["buildings"].size())
	assert_int(pack.buildings.size()).is_greater(5000)
	var names := []
	for b in pack.buildings:
		if b.name != "":
			names.append(b.name)
	assert_array(names).contains(["West Memorial Building"])
	assert_int(pack.building_chunks["lod0"].size()).is_greater(100)


func _tris_with(tris: RoadMeshBuilder.ChunkTriangles, uv2_x: float) -> int:
	var n := 0
	for i in range(0, tris.vertices.size(), 3):
		if absf(tris.uv2s[i].x - uv2_x) < 0.01:
			n += 1
	return n


func test_untagged_house_gets_a_pitched_roof_above_the_eave() -> void:
	var b := _box("w5.0", 20.0, 20.0, 5.0, 7.0, 0.0)
	b.roof_shape = ""
	var tris: RoadMeshBuilder.ChunkTriangles = BuildingBuilder.build([b])["lod0"][Vector2i(0, 0)]
	var box := BuildingBuilder.oriented_box(b.rings[0])
	assert_float(box["fill"]).is_equal_approx(1.0, 1e-3)
	assert_str(BuildingBuilder.roof_style_for(b, box)).is_not_equal("flat")
	var top := 0.0
	for v in tris.vertices:
		top = maxf(top, v.y)
	assert_float(top).is_greater(7.0 + 1.0)  # a ridge above the eave
	assert_int(_tris_with(tris, -1.0)).is_greater(2)  # more than the flat cap


func test_apartments_get_balconies_and_shops_get_shopfront_walls() -> void:
	var flats := _box("w6.0", 20.0, 20.0, 8.0, 20.0, 0.0)  # 16 m walls
	flats.kind = "apartments"
	var shop := _box("w7.0", 60.0, 60.0, 5.0, 7.0, 0.0)  # 10 m walls
	shop.kind = "retail"
	shop.shopfront = true
	var result := BuildingBuilder.build([flats, shop])
	var tris: RoadMeshBuilder.ChunkTriangles = result["lod0"][Vector2i(0, 0)]
	assert_int(_tris_with(tris, BuildingBuilder.TRIM_UV2)).is_greater(40)  # balcony slabs and a parapet
	var shopfront_walls := 0
	for i in range(0, tris.vertices.size(), 3):
		if tris.uv2s[i].x >= float(BuildingBuilder.SHOPFRONT_FLAG):
			shopfront_walls += 1
	assert_int(shopfront_walls).is_equal(8)  # the shop's four walls, two triangles each


func test_tagged_colour_and_material_win() -> void:
	assert_object(BuildingBuilder.parse_colour("#aabbcc")).is_equal(Color.html("#aabbcc"))
	assert_object(BuildingBuilder.parse_colour("red")).is_equal(BuildingBuilder.NAMED_COLOURS["red"])
	assert_object(BuildingBuilder.parse_colour("")).is_equal(Color.TRANSPARENT)
	var b := _box("w8.0", 0.0, 0.0, 5.0, 7.0, 0.0)
	b.colour = "#112233"
	assert_object(BuildingBuilder.color_for(b)).is_equal(Color.html("#112233"))
	assert_int(BuildingBuilder.treatment_of("office", 30.0, "brick", 0.1)).is_equal(BuildingBuilder.TREATMENT_PUNCHED)
	assert_int(BuildingBuilder.treatment_of("house", 7.0, "glass", 0.9)).is_equal(BuildingBuilder.TREATMENT_CURTAIN)
	assert_int(BuildingBuilder.treatment_of("house", 7.0, "", 0.2)).is_equal(BuildingBuilder.TREATMENT_STUCCO)
	assert_int(BuildingBuilder.treatment_of("house", 7.0, "", 0.8)).is_equal(BuildingBuilder.TREATMENT_PUNCHED)


## #80: OSM `building=roof` is a canopy. The hospital drop-off's was built as a solid block from
## the ground and boxed in the respawn under it; now nothing stands below the slab except a
## thin post at each corner.
func test_a_roof_building_is_a_canopy_open_underneath() -> void:
	var b := _box("w1.0", 0.0, 0.0, 6.0, 3.2, 10.0)
	b.kind = "roof"
	var built := BuildingBuilder.build([b] as Array[BuildingBuilder.Building])
	var tris: RoadMeshBuilder.ChunkTriangles = (built["lod0"] as Dictionary).values()[0]
	var mesh := tris.to_mesh()
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var slab_bottom := 10.0 + 3.2 - BuildingBuilder.CANOPY_THICK_M
	var low := 0
	for v in verts:
		if v.y < slab_bottom - 0.01:
			low += 1
			# Below the slab only the corner posts: within a post's width of a corner.
			assert_float(minf(absf(absf(v.x) - 6.0), absf(absf(v.z) - 6.0))).is_less(BuildingBuilder.CANOPY_POST_M * 2.0)
			assert_bool(absf(v.x) > 5.0 and absf(v.z) > 5.0).override_failure_message("something below the canopy away from its corners at %s" % v).is_true()
	assert_int(low).is_greater(0)  # the posts are there
