extends GdUnitTestSuite
## The map data's credits: every attribution line for the full map, the OpenStreetMap line
## for under the minimap.


func test_lines_and_the_short_osm_line() -> void:
	var m := {"attribution": ["Elevation: HRDEM, Natural Resources Canada", "© OpenStreetMap contributors", ""]}
	assert_array(Array(MapCredits.lines(m))).has_size(2)
	assert_str(MapCredits.short_line(m)).is_equal("© OpenStreetMap contributors")
	assert_str(MapCredits.short_line({"attribution": "Made by hand"})).is_equal("Made by hand")
	assert_str(MapCredits.short_line({})).is_equal("")


func test_the_ottawa_pack_credits_openstreetmap() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../packs/ottawa-centretown").simplify_path()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("pack.json")))
	assert_str(MapCredits.short_line(manifest)).contains("OpenStreetMap")
	assert_int(MapCredits.lines(manifest).size()).is_greater_equal(2)  # OSM and the elevation
