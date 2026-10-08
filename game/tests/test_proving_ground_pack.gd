extends GdUnitTestSuite
## The Double Cross proving ground pack as the game sees it (add-proving-ground): found by id,
## its fixed spawn on the start straight facing south, its loop road under the spawn.

const PACK_ID := "code430.proving-ground"

var _pack: MapPack


func before() -> void:
	var dir := PackLocator.find_pack(PACK_ID)
	assert_str(dir).override_failure_message("pack not found; searched %s" % [PackLocator.search_dirs()]).is_not_empty()
	_pack = MapPack.new()
	assert_bool(_pack.load(dir)).is_true()


func test_pack_is_small_and_complete() -> void:
	assert_int(_pack.chunk_coords().size()).is_equal(_pack.terrain_index["chunks"].size())
	assert_int(_pack.chunk_coords().size()).is_between(60, 100)
	assert_str(str(_pack.manifest.get("name", ""))).is_equal("Double Cross")


func test_spawn_is_the_manifests_fixed_start() -> void:
	var fixed := _pack.manifest_spawn()
	assert_bool(fixed.is_empty()).is_false()
	var t := _pack.spawn_transform()
	assert_float(t.origin.x).is_equal_approx(float(fixed["x"]), 0.01)
	assert_float(t.origin.z).is_equal_approx(float(fixed["z"]), 0.01)
	# At road height plus a metre, not at sea level.
	assert_float(t.origin.y).is_greater(50.0)
	# Heading 180 is south (+z on this map).
	var forward := -t.basis.z
	assert_float(forward.dot(Vector3(0.0, 0.0, 1.0))).is_greater(0.99)


func test_spawn_edge_is_the_loop_road() -> void:
	var e := _pack.spawn_edge()
	assert_object(e).is_not_null()
	assert_str(e.name).is_equal("Double Cross Loop")
	var hit := _pack.graph.nearest_edge(_pack.spawn_transform().origin, 30.0)
	assert_bool(hit.is_empty()).is_false()
	assert_float(hit["distance"]).is_less(8.0)


func test_ottawa_pack_keeps_its_highway_spawn() -> void:
	# A pack without a fixed spawn still starts on its highway: the manifest rule is opt in.
	var dir := PackLocator.find_pack("code430.ottawa-centretown")
	var ottawa := MapPack.new()
	assert_bool(ottawa.load(dir)).is_true()
	assert_bool(ottawa.manifest_spawn().is_empty()).is_true()
	assert_str(ottawa.spawn_edge().road_class).is_equal("motorway")
