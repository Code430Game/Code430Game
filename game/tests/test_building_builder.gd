extends GdUnitTestSuite
## Building extrusion: outward walls, upward roofs, chunk assignment, and the Ottawa pack file.

const PACK_ID := "code430.ottawa-centretown"


func _box(id: String, cx: float, cz: float, half: float, height: float, ground: float, ccw: bool = true) -> BuildingBuilder.Building:
	var b := BuildingBuilder.Building.new()
	b.id = id
	b.kind = "house"
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
