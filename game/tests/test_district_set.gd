extends GdUnitTestSuite
## add-district-stitching 2.1-2.3: two neighbouring districts (slices of the proving ground on
## either side of x = 256 m, tests/fixtures/districts, from regions/test-districts) load as one
## map: roads join at their shared border, each chunk comes from its owner, the roadblocks at
## joined crossings go, and a set that doesn't fit is refused with a reason.

const WEST := "res://tests/fixtures/districts/west"
const EAST := "res://tests/fixtures/districts/east"
const LINE_X := 256.0


func _manifest(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path.path_join("pack.json")))


func test_a_set_must_share_an_origin_have_borders_and_not_overlap() -> void:
	var w := _manifest(WEST)
	var e := _manifest(EAST)
	assert_str(DistrictSet.refusal([w, e])).is_empty()
	var moved := e.duplicate(true)
	moved["map"]["origin"]["easting"] = 1.0
	assert_str(DistrictSet.refusal([w, moved])).contains("origin")
	var overlap := e.duplicate(true)
	overlap["map"]["border"] = {"chunks": [0, -2, 2, 0]}
	assert_str(DistrictSet.refusal([w, overlap])).contains("overlaps")
	var none := e.duplicate(true)
	(none["map"] as Dictionary).erase("border")
	assert_str(DistrictSet.refusal([w, none])).contains("no border")


func test_two_districts_load_as_one_map_joined_at_the_border() -> void:
	var west: MapPack = auto_free(MapPack.new())
	assert_bool(west.load(WEST)).is_true()
	var both: MapPack = auto_free(MapPack.new())
	assert_bool(both.load_districts(PackedStringArray([WEST, EAST]))).is_true()
	assert_array(Array(both.districts)).contains_exactly(["test.district-west", "test.district-east"])
	assert_int(both.joined_crossings).is_equal(7)
	# Roads now run across the line: edges with points on both sides of it.
	var across := 0
	for e: RoadGraph.RoadEdge in both.graph.edges.values():
		var west_side := false
		var east_side := false
		for p in e.polyline:
			west_side = west_side or p.x < LINE_X - 1.0
			east_side = east_side or p.x > LINE_X + 1.0
		if west_side and east_side:
			across += 1
	assert_int(across).is_greater_equal(1)
	# No dead end is left on the shared line, and every edge's nodes exist.
	for n: RoadGraph.RoadNode in both.graph.nodes.values():
		if absf(n.position.x - LINE_X) < 0.01:
			assert_str(n.junction_type).is_not_equal("dead_end")
	for e: RoadGraph.RoadEdge in both.graph.edges.values():
		assert_bool(both.graph.nodes.has(e.from_node) and both.graph.nodes.has(e.to_node)).is_true()
	# No roadblock stands on the shared line any more; the outer ones stay.
	var on_line := 0
	var outer := 0
	for b in both.barriers:
		if b.kind != "roadblock":
			continue
		var mid := (b.points[0] + b.points[b.points.size() - 1]) * 0.5
		if absf(mid.x - LINE_X) < 4.0:
			on_line += 1
		else:
			outer += 1
	assert_int(on_line).is_equal(0)
	assert_int(outer).is_greater(0)
	var west_blocks := 0
	for b in west.barriers:
		if b.kind == "roadblock" and b.border_side == "east":
			west_blocks += 1
	assert_int(west_blocks).is_greater(0)  # on its own, the west district still ends there


func test_each_chunk_comes_from_the_district_that_owns_it() -> void:
	var both: MapPack = auto_free(MapPack.new())
	assert_bool(both.load_districts(PackedStringArray([WEST, EAST]))).is_true()
	var coords := {}
	for entry: Dictionary in both.terrain_index["chunks"]:
		var c := Vector2i(int(entry["cx"]), int(entry["cz"]))
		assert_bool(coords.has(c)).is_false()  # one entry per chunk
		coords[c] = str(entry["dir"])
	assert_array(coords.keys()).contains_exactly_in_any_order([Vector2i(0, -2), Vector2i(0, -1), Vector2i(1, -2), Vector2i(1, -1)])
	assert_str(coords[Vector2i(0, -1)]).is_equal(WEST)
	assert_str(coords[Vector2i(1, -1)]).is_equal(EAST)
	# The ground reads from the owner's files on both sides.
	assert_bool(is_nan(both.ground_height(100.0, -100.0))).is_false()
	assert_bool(is_nan(both.ground_height(400.0, -100.0))).is_false()
	# A building is kept once, by the district holding its centre.
	var ids := {}
	for b in both.buildings:
		assert_bool(ids.has(b.id)).is_false()
		ids[b.id] = true


func test_one_district_loads_as_before() -> void:
	var one: MapPack = auto_free(MapPack.new())
	assert_bool(one.load_districts(PackedStringArray([WEST]))).is_true()
	assert_bool(one.districts.is_empty()).is_true()
	var refused: MapPack = auto_free(MapPack.new())
	var w := _manifest(WEST)
	assert_bool(refused.load_districts(PackedStringArray([WEST, WEST]))).is_false()
	assert_str(refused.set_refusal).contains("overlaps")


func test_the_loader_finds_a_maps_neighbouring_districts() -> void:
	var saved_dirs := PackLoader.search_dirs
	var saved_map := PackLoader.active_map
	PackLoader.search_dirs = PackedStringArray([ProjectSettings.globalize_path("res://tests/fixtures/districts")])
	PackLoader.reload()
	assert_array(Array(PackLoader.district_ids("test.district-west"))).contains_exactly(["test.district-east"])
	var dirs := PackLoader.district_dirs("test.district-west")
	assert_int(dirs.size()).is_equal(2)
	assert_str(dirs[0]).ends_with("west")
	PackLoader.set_active_map("test.district-west")
	assert_bool(PackLoader.loaded_ids.has("test.district-east")).is_true()  # in the co-op summary
	PackLoader.search_dirs = saved_dirs
	PackLoader.active_map = saved_map
	PackLoader.reload()


func test_a_set_builds_the_meshes_once_for_the_whole_map() -> void:
	# The districts only read their data; the set builds markings, sidewalks and buildings for
	# both sides of the border, and times each step.
	var set_pack: MapPack = auto_free(MapPack.new())
	assert_bool(set_pack.load_districts(PackedStringArray([WEST, EAST]))).is_true()
	var west := false
	var east := false
	for coord: Vector2i in set_pack.marking_chunks:
		west = west or coord.x * RoadGeometry.CHUNK_SIZE_M < LINE_X
		east = east or coord.x * RoadGeometry.CHUNK_SIZE_M >= LINE_X
	assert_bool(west and east).override_failure_message("markings missing a side of the border").is_true()
	assert_bool(set_pack.sidewalk_chunks.is_empty()).is_false()  # the fixture's footways are all east
	assert_bool((set_pack.building_chunks["lod0"] as Dictionary).is_empty()).is_false()
	var steps := ", ".join(set_pack.step_times.map(func(s: Array) -> String: return str(s[0])))
	assert_str(steps).contains("west: building meshes").contains("east: roads").contains("joining the districts")



func test_a_district_loading_into_a_set_builds_no_meshes_of_its_own() -> void:
	# The same district, alone and as part of a set: the data is the same, the meshes only alone.
	var alone: MapPack = auto_free(MapPack.new())
	assert_bool(alone.load(EAST)).is_true()
	var part: MapPack = auto_free(MapPack.new())
	part._sink = auto_free(MapPack.new())
	assert_bool(part.load(EAST)).is_true()
	assert_int(part.buildings.size()).is_equal(alone.buildings.size())
	assert_int(part.barriers.size()).is_equal(alone.barriers.size())
	assert_bool(alone.marking_chunks.is_empty() or (alone.building_chunks["lod0"] as Dictionary).is_empty()).is_false()
	assert_bool(part.marking_chunks.is_empty()).is_true()
	assert_bool((part.building_chunks["lod0"] as Dictionary).is_empty()).is_true()
	assert_bool(part.sidewalk_chunks.is_empty()).is_true()
	assert_bool(part.barrier_chunks.is_empty()).is_true()
	assert_bool(part._graph_dict.is_empty()).is_false()  # kept for the join
