extends GdUnitTestSuite
## Tests for the Settings autoload: preset resolution, override, persistence.

const SettingsScript := preload("res://core/settings/settings.gd")

var _tmp_path: String


func before_test() -> void:
	_tmp_path = "user://test_settings_%d.cfg" % Time.get_ticks_usec()


func after_test() -> void:
	if FileAccess.file_exists(_tmp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_tmp_path))


func _make(on_deck: bool) -> Node:
	var s: Node = SettingsScript.new()
	s.settings_path = _tmp_path
	s.presets = SettingsScript.load_presets(SettingsScript.PRESETS_PATH)
	s.is_steam_deck = on_deck
	s.load_settings()
	return auto_free(s)


func test_presets_load() -> void:
	var presets := SettingsScript.load_presets(SettingsScript.PRESETS_PATH)
	assert_dict(presets).contains_keys(["deck", "high"])
	assert_dict(presets).not_contains_keys(["_comment"])


func test_every_feature_declared_in_both_presets() -> void:
	var presets := SettingsScript.load_presets(SettingsScript.PRESETS_PATH)
	var deck_keys: Array = presets["deck"].keys()
	var high_keys: Array = presets["high"].keys()
	deck_keys.sort()
	high_keys.sort()
	assert_array(deck_keys).is_equal(high_keys)


func test_deck_preset_disables_sdfgi() -> void:
	var presets := SettingsScript.load_presets(SettingsScript.PRESETS_PATH)
	assert_bool(presets["deck"]["sdfgi"]).is_false()


func test_auto_on_deck_resolves_to_deck() -> void:
	assert_str(_make(true).resolve_preset_name()).is_equal("deck")


func test_auto_on_desktop_resolves_to_high() -> void:
	assert_str(_make(false).resolve_preset_name()).is_equal("high")


func test_override_beats_hardware() -> void:
	var s := _make(true)
	s.set_preset_override("high")
	assert_str(s.resolve_preset_name()).is_equal("high")
	assert_str(s.current_preset_name).is_equal("high")


func test_unknown_override_is_ignored() -> void:
	var s := _make(true)
	s.set_preset_override("ultra")
	assert_str(s.preset_override).is_equal("auto")


func test_override_persists_across_instances() -> void:
	var first := _make(true)
	first.set_preset_override("high")
	var second := _make(true)
	assert_str(second.preset_override).is_equal("high")
	assert_str(second.resolve_preset_name()).is_equal("high")


func test_apply_to_environment_follows_preset() -> void:
	var s := _make(false)
	s.apply_preset("deck")
	var env := Environment.new()
	env.sdfgi_enabled = true
	s.apply_to_environment(env)
	assert_bool(env.sdfgi_enabled).is_false()
	s.apply_preset("high")
	s.apply_to_environment(env)
	assert_bool(env.sdfgi_enabled).is_true()
