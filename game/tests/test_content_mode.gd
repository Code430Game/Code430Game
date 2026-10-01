extends GdUnitTestSuite
## Tone modes: defaults, persistence, allowances, variant selection and billboards.

var _path: String


func before_test() -> void:
	_path = "user://tmp/settings_%d.cfg" % Time.get_ticks_usec()
	ContentMode.settings_path = _path
	ContentMode.locked = false
	ContentMode.load_saved()


func after_test() -> void:
	ContentMode.settings_path = ContentMode.DEFAULT_SETTINGS_PATH
	ContentMode.locked = false
	ContentMode.set_mode("gritty", false)
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


func test_fresh_install_is_gritty_and_a_choice_persists() -> void:
	assert_str(ContentMode.current).is_equal("gritty")
	assert_bool(ContentMode.set_mode("clean")).is_true()
	ContentMode.set_mode("dystopia", false)
	ContentMode.load_saved()
	assert_str(ContentMode.current).is_equal("clean")
	assert_bool(ContentMode.set_mode("grimdark")).is_false()
	assert_array(Array(ContentMode.ids())).contains_exactly(["clean", "gritty", "dystopia"])


func test_allowances_and_flags_per_mode() -> void:
	ContentMode.set_mode("clean", false)
	assert_bool(ContentMode.allows("violence")).is_false()
	assert_bool(ContentMode.allows("violence", "stylized")).is_true()
	assert_bool(ContentMode.allows("gore", "mild")).is_false()
	assert_bool(ContentMode.allows("spiders", "none")).is_false()
	assert_bool(ContentMode.flag("violence")).is_false()
	ContentMode.set_mode("gritty", false)
	assert_bool(ContentMode.allows("gore")).is_true()
	assert_bool(ContentMode.allows("dystopia_tech", "mild")).is_false()
	assert_bool(ContentMode.flag("lethal_weapons")).is_true()
	ContentMode.set_mode("dystopia", false)
	assert_bool(ContentMode.allows("dystopia_tech")).is_true()


func test_variant_selection_prefers_the_mode_then_the_fallback_then_hides() -> void:
	var ad := {"id": "ad.t", "variants": {
		"dystopia": {"text": "D", "descriptors": {"dystopia_tech": "strong"}},
		"fallback": {"text": "F"},
	}}
	ContentMode.set_mode("dystopia", false)
	assert_str(ContentMode.pick_variant(ad)["text"]).is_equal("D")
	ContentMode.set_mode("clean", false)
	assert_str(ContentMode.pick_variant(ad)["text"]).is_equal("F")
	var bail := {"id": "ad.bail", "variants": {"fallback": {"text": "B", "descriptors": {"crime": "strong"}}}}
	assert_bool(ContentMode.pick_variant(bail).is_empty()).is_true()
	ContentMode.set_mode("gritty", false)
	assert_str(ContentMode.pick_variant(bail)["text"]).is_equal("B")


func _edge(id: String, length: float) -> RoadGraph.RoadEdge:
	var e := RoadGraph.RoadEdge.new()
	e.id = id
	e.road_class = "primary"
	e.width_m = 14.0
	e.polyline = PackedVector3Array([Vector3(0, 0, 0), Vector3(length, 0, 0)])
	return e


func test_billboards_are_deterministic_and_follow_the_mode() -> void:
	var ads: Array = [
		{"id": "ad.a", "variants": {"clean": {"text": "A clean"}, "fallback": {"text": "A", "descriptors": {"profanity": "mild"}}}},
		{"id": "ad.b", "variants": {"fallback": {"text": "B"}}},
		{"id": "ad.c", "variants": {"fallback": {"text": "C", "descriptors": {"crime": "strong"}}}},
	]
	var edges: Array = [_edge("e1", 900.0), _edge("e2", 500.0)]
	ContentMode.set_mode("gritty", false)
	var one: Billboards = auto_free(Billboards.new())
	add_child(one)
	one.setup(edges, ads, 7)
	var two: Billboards = auto_free(Billboards.new())
	add_child(two)
	two.setup(edges, ads, 7)
	assert_int(one.count()).is_equal(4 + 2)
	assert_int(one._panels.multimesh.instance_count).is_equal(6)
	var ids_one: Array = []
	for s in one.sites:
		ids_one.append(s["ad"]["id"])
	var ids_two: Array = []
	for s in two.sites:
		ids_two.append(s["ad"]["id"])
	assert_array(ids_one).is_equal(ids_two)
	var gritty := one.texts()
	ContentMode.set_mode("clean", false)
	var clean := one.texts()
	for i in range(one.count()):
		var id: String = ids_one[i]
		if id == "ad.a":
			assert_str(gritty[i]).is_equal("A")
			assert_str(clean[i]).is_equal("A clean")
		elif id == "ad.c":
			assert_str(gritty[i]).is_equal("C")
			assert_str(clean[i]).is_equal("")
