extends GdUnitTestSuite
## add-vegetation 2.x: archetype budgets, per-chunk caps that keep mapped trees, trunks on
## street trees, and green areas for the maps.

const PACK_ID := "code430.ottawa-centretown"


func test_archetypes_stay_under_their_triangle_budgets() -> void:
	for a in TreeMeshes.ARCHETYPES:
		var lod0 := TreeMeshes.triangles(TreeMeshes.mesh(a, 0))
		var lod1 := TreeMeshes.triangles(TreeMeshes.mesh(a, 1))
		var budget := 40 if TreeMeshes.is_bush(a) else 150
		assert_int(lod0).override_failure_message("%s LOD0 has %d triangles" % [a, lod0]).is_less_equal(budget)
		assert_int(lod1).override_failure_message("%s LOD1 has %d triangles" % [a, lod1]).is_less(lod0)
		assert_int(lod1).is_less_equal(30)


func test_both_presets_declare_vegetation() -> void:
	var presets := Settings.load_presets(Settings.PRESETS_PATH)
	for name: String in ["deck", "high"]:
		for key in ["vegetation_trees_per_chunk", "vegetation_bushes_per_chunk", "vegetation_lod0_m", "vegetation_sway"]:
			assert_bool((presets[name] as Dictionary).has(key)).override_failure_message("%s lacks %s" % [name, key]).is_true()
	assert_bool(presets["deck"]["vegetation_sway"]).is_false()
	assert_bool(presets["high"]["vegetation_sway"]).is_true()


func test_a_cap_keeps_mapped_trees_before_scattered_ones() -> void:
	var by_chunk := VegetationBuilder.load_by_chunk(PackLocator.find_pack(PACK_ID), RoadGeometry.CHUNK_SIZE_M)
	assert_int(by_chunk.size()).is_greater(50)
	var busiest: Dictionary = {}
	for c in by_chunk:
		if (by_chunk[c]["trees"] as Array).size() > (busiest.get("trees", []) as Array).size():
			busiest = by_chunk[c]
	var all: Array = busiest["trees"]
	var kept: Array = VegetationBuilder.capped(busiest)["trees"]
	assert_int(kept.size()).is_equal(mini(all.size(), int(VegetationBuilder.preset_value("vegetation_trees_per_chunk", 400))))
	var tagged_total := all.filter(func(r: Array) -> bool: return r[7] == "tagged").size()
	var tagged_kept := kept.filter(func(r: Array) -> bool: return r[7] == "tagged").size()
	assert_int(tagged_kept).is_equal(mini(tagged_total, kept.size()))  # mapped trees survive the cap first


func test_a_near_chunk_gets_both_lods_and_street_tree_trunks() -> void:
	var by_chunk := VegetationBuilder.load_by_chunk(PackLocator.find_pack(PACK_ID), RoadGeometry.CHUNK_SIZE_M)
	var coord := Vector2i.ZERO
	for c: Vector2i in by_chunk:
		if (by_chunk[c]["trees"] as Array).any(func(r: Array) -> bool: return r[7] == "tagged"):
			coord = c
			break
	var chunk: Node3D = auto_free(Node3D.new())
	var trunks := VegetationBuilder.add_to_chunk(chunk, by_chunk[coord], true)
	assert_object(trunks).is_not_null()
	var lod0 := 0
	var lod1 := 0
	for child in chunk.get_node("vegetation").get_children():
		if String(child.name).ends_with("_lod0"):
			lod0 += 1
		elif String(child.name).ends_with("_lod1"):
			lod1 += 1
	assert_int(lod0).is_greater(0)
	assert_int(lod1).is_equal(lod0)
	var mid: Node3D = auto_free(Node3D.new())
	assert_object(VegetationBuilder.add_to_chunk(mid, by_chunk[coord], false)).is_null()  # MID: no trunks
	for child in mid.get_node("vegetation").get_children():
		assert_bool(String(child.name).ends_with("_lod1")).is_true()


func test_green_areas_load_for_the_maps() -> void:
	var areas := VegetationBuilder.load_areas(PackLocator.find_pack(PACK_ID))
	assert_int(areas.size()).is_greater(100)
	var kinds := {}
	for a: Dictionary in areas:
		kinds[a["kind"]] = true
		assert_int((a["triangles"] as PackedInt32Array).size() % 3).is_equal(0)
	assert_bool(kinds.has("park")).is_true()


func test_downgrading_a_chunk_drops_lod0_and_lets_lod1_stand_in() -> void:
	var by_chunk := VegetationBuilder.load_by_chunk(PackLocator.find_pack(PACK_ID), RoadGeometry.CHUNK_SIZE_M)
	var chunk: Node3D = auto_free(Node3D.new())
	VegetationBuilder.add_to_chunk(chunk, by_chunk[by_chunk.keys()[0]], true)
	MapPack.downgrade_chunk(chunk)
	await get_tree().process_frame
	for child in chunk.get_node("vegetation").get_children():
		assert_bool(String(child.name).ends_with("_lod1")).is_true()
		assert_float((child as GeometryInstance3D).visibility_range_begin).is_equal(0.0)
