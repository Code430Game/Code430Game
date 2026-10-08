extends GdUnitTestSuite
## PackLoader (add-pack-loader): discovery over fixture dirs, manifest and file checks,
## dependency order, namespaces, the enabled set, the registry and the co-op summary.

var _fixtures: String
var _more: String
var _cfg: String
var _saved_dirs: PackedStringArray
var _saved_path: String
var _saved_map: String
var _saved_mode: String


func before_test() -> void:
	_fixtures = ProjectSettings.globalize_path("res://tests/fixtures/packs")
	_more = ProjectSettings.globalize_path("res://tests/fixtures/packs_more")
	_cfg = "user://tmp/packs_%d.cfg" % Time.get_ticks_usec()
	_saved_dirs = PackLoader.search_dirs
	_saved_path = PackLoader.enabled_path
	_saved_map = PackLoader.active_map
	_saved_mode = ContentMode.current
	PackLoader.enabled_path = _cfg
	PackLoader.pinned = PackedStringArray()
	PackLoader._pinned = false


func after_test() -> void:
	ContentMode.set_mode(_saved_mode, false)
	PackLoader.pinned = PackedStringArray()
	PackLoader._pinned = false
	PackLoader.search_dirs = _saved_dirs
	PackLoader.enabled_path = _saved_path
	PackLoader.active_map = _saved_map
	PackLoader.reload()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg))


## Fixtures plus the repo packs, with the Ottawa map active.
func _load_fixtures(extra: PackedStringArray = PackedStringArray()) -> void:
	var repo := ProjectSettings.globalize_path("res://").path_join("../packs").simplify_path()
	var dirs := PackedStringArray([_fixtures])
	dirs.append_array(extra)
	dirs.append(repo)
	PackLoader.search_dirs = dirs
	PackLoader.active_map = "code430.ottawa-centretown"
	PackLoader.reload()


func test_discovers_fixture_and_first_party_packs_with_reasons() -> void:
	_load_fixtures()
	var alpha: PackLoader.PackInfo = PackLoader.packs["test.story-alpha"]
	assert_bool(alpha.valid).is_true()
	assert_int(alpha.schema_version).is_equal(1)
	assert_int(alpha.content.size()).is_equal(1)
	var old: PackLoader.PackInfo = PackLoader.packs["test.old-style"]
	assert_bool(old.valid).is_true()
	assert_array(old.content).contains([{"type": "ads", "path": "ads.v0.json"}])  # synthesised v0 index
	var future: PackLoader.PackInfo = PackLoader.packs["test.future"]
	assert_bool(future.valid).is_false()
	assert_str(future.reason).contains("schema_version 9")
	assert_bool(PackLoader.packs.has("code430.characters")).is_true()
	assert_bool(PackLoader.packs.has("code430.ottawa-centretown")).is_true()


func test_loaded_order_puts_the_active_map_first_and_skips_unmet_dependencies() -> void:
	_load_fixtures()
	assert_str(PackLoader.loaded_ids[0]).is_equal("code430.ottawa-centretown")
	assert_bool(PackLoader.loaded_ids.has("test.story-alpha")).is_true()
	assert_bool(PackLoader.loaded_ids.has("test.old-style")).is_true()
	assert_bool(PackLoader.loaded_ids.has("code430.characters")).is_true()
	# Beta needs alpha ^2.0 and alpha is 1.2.0: disabled with both names and the range.
	assert_bool(PackLoader.loaded_ids.has("test.story-beta")).is_false()
	var beta: PackLoader.PackInfo = PackLoader.packs["test.story-beta"]
	assert_str(beta.reason).contains("test.story-alpha")
	assert_str(beta.reason).contains("^2.0")
	assert_str(beta.reason).contains("1.2.0")
	# The other map pack is discovered and available but not loaded.
	assert_bool(PackLoader.loaded_ids.has("code430.proving-ground")).is_false()
	assert_bool(PackLoader.map_pack_ids().has("code430.proving-ground")).is_true()


func test_same_id_in_two_dirs_takes_the_most_specific_and_logs_the_other() -> void:
	_load_fixtures(PackedStringArray([_more]))
	var alpha: PackLoader.PackInfo = PackLoader.packs["test.story-alpha"]
	assert_str(alpha.version).is_equal("1.2.0")
	assert_int(alpha.shadowed.size()).is_equal(1)
	assert_str(alpha.shadowed[0]).contains("story-alpha-copy")


func test_resolve_stays_inside_the_pack() -> void:
	_load_fixtures()
	var ok := PackLoader.resolve("test.story-alpha:ads/promo.json")
	assert_str(ok).ends_with("story-alpha/ads/promo.json")
	assert_str(PackLoader.resolve("test.story-alpha:../old-style/ads.v0.json")).is_empty()
	assert_str(PackLoader.resolve("test.story-alpha:/etc/passwd")).is_empty()
	assert_str(PackLoader.resolve("test.story-beta:ads.v0.json")).is_empty()  # not loaded
	assert_str(PackLoader.resolve("test.story-alpha:nope.json")).is_empty()
	assert_str(PackLoader.resolve("no-colon")).is_empty()


func test_registry_merges_ads_across_packs_and_filters_by_mode() -> void:
	_load_fixtures()
	ContentMode.set_mode("gritty", false)
	var ids := _ad_ids()
	assert_bool(ids.has("alpha.mild")).is_true()
	assert_bool(ids.has("alpha.heist")).is_true()
	assert_bool(ids.has("old.one")).is_true()
	assert_bool(ids.has("beta.only")).is_false()
	var ottawa_count := 0
	for item in PackLoader.items("ads"):
		if item["pack_id"] == "code430.ottawa-centretown":
			ottawa_count += 1
		assert_bool(item.has("source")).is_true()
	assert_int(ottawa_count).is_greater(0)
	ContentMode.set_mode("clean", false)
	var clean_ids := _ad_ids()
	assert_bool(clean_ids.has("alpha.mild")).is_true()
	assert_bool(clean_ids.has("alpha.heist")).is_false()  # crime strong is above clean


func test_disabling_a_pack_removes_its_items_after_reload_and_is_saved() -> void:
	_load_fixtures()
	assert_bool(PackLoader.set_enabled("test.old-style", false)).is_true()
	PackLoader.reload()
	assert_bool(PackLoader.loaded_ids.has("test.old-style")).is_false()
	assert_bool(_ad_ids().has("old.one")).is_false()
	var cfg := ConfigFile.new()
	assert_int(cfg.load(_cfg)).is_equal(OK)
	var enabled: PackedStringArray = cfg.get_value(PackLoader.SECTION, PackLoader.KEY_ENABLED)
	assert_bool(enabled.has("test.old-style")).is_false()
	assert_bool(enabled.has("test.story-alpha")).is_true()
	# Map packs cannot be toggled here.
	assert_bool(PackLoader.set_enabled("code430.ottawa-centretown", false)).is_false()


func test_new_pack_is_enabled_and_announced_once() -> void:
	_load_fixtures()
	assert_bool((PackLoader.packs["test.story-alpha"] as PackLoader.PackInfo).announced).is_true()
	PackLoader.reload()
	assert_bool((PackLoader.packs["test.story-alpha"] as PackLoader.PackInfo).announced).is_false()


func test_pinned_set_wins_without_touching_the_saved_set() -> void:
	_load_fixtures()
	PackLoader.pin(PackedStringArray(["test.old-style"]))
	assert_bool(PackLoader.loaded_ids.has("test.old-style")).is_true()
	assert_bool(PackLoader.loaded_ids.has("test.story-alpha")).is_false()
	assert_bool(PackLoader.loaded_ids.has("code430.ottawa-centretown")).is_true()
	var cfg := ConfigFile.new()
	cfg.load(_cfg)
	var enabled: PackedStringArray = cfg.get_value(PackLoader.SECTION, PackLoader.KEY_ENABLED, PackedStringArray())
	assert_bool(enabled.has("test.story-alpha")).is_true()


func test_manifest_summary_is_sorted_and_hashes_once() -> void:
	_load_fixtures()
	var summary := PackLoader.manifest_summary()
	var ids: Array = []
	for row: Dictionary in summary:
		ids.append(row["id"])
		assert_str(row["hash"]).has_length(64)
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	assert_array(ids).is_equal(sorted_ids)
	assert_bool(ids.has("code430.ottawa-centretown")).is_true()
	assert_bool(ids.has("test.story-alpha")).is_true()
	var again := PackLoader.manifest_summary()
	assert_array(again).is_equal(summary)
	var ottawa := PackLoader.map_pack_dir("code430.ottawa-centretown")
	assert_str(PackLoader.cached_hash("code430.ottawa-centretown")).is_equal(MapPack.content_hash(ottawa))


func test_semver_ranges() -> void:
	assert_bool(PackLoader.semver_satisfies("1.2.3", "1.2.3")).is_true()
	assert_bool(PackLoader.semver_satisfies("1.2.4", "1.2.3")).is_false()
	assert_bool(PackLoader.semver_satisfies("1.9.0", "^1.2")).is_true()
	assert_bool(PackLoader.semver_satisfies("2.0.0", "^1.2")).is_false()
	assert_bool(PackLoader.semver_satisfies("0.3.5", "^0.3")).is_true()
	assert_bool(PackLoader.semver_satisfies("0.4.0", "^0.3")).is_false()
	assert_bool(PackLoader.semver_satisfies("1.2.9", "~1.2.3")).is_true()
	assert_bool(PackLoader.semver_satisfies("1.3.0", "~1.2.3")).is_false()
	assert_bool(PackLoader.semver_satisfies("1.5.0", ">=1.0 <2.0")).is_true()
	assert_bool(PackLoader.semver_satisfies("2.0.0", ">=1.0 <2.0")).is_false()
	assert_bool(PackLoader.semver_satisfies("3.1.0", "*")).is_true()
	assert_bool(PackLoader.semver_satisfies("nope", "*")).is_false()


func test_script_inside_a_story_pack_refuses_the_pack() -> void:
	var dir := ProjectSettings.globalize_path("user://tmp/badpacks_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir.path_join("evil/sub"))
	_write(dir.path_join("evil/pack.json"), JSON.stringify({
		"schema_version": 0, "id": "test.evil", "name": "Evil", "version": "1.0.0", "type": "story",
		"engine_api": 0, "license": "MIT", "attribution": ["x"],
	}))
	_write(dir.path_join("evil/sub/payload.gd"), "extends Node")
	PackLoader.search_dirs = PackedStringArray([dir])
	PackLoader.active_map = ""
	PackLoader.reload()
	var evil: PackLoader.PackInfo = PackLoader.packs["test.evil"]
	assert_bool(evil.valid).is_false()
	assert_str(evil.reason).contains("sub/payload.gd")
	assert_bool(PackLoader.loaded_ids.has("test.evil")).is_false()


func _ad_ids() -> Array:
	var out: Array = []
	for item in PackLoader.items("ads"):
		out.append(item["id"])
	return out


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
