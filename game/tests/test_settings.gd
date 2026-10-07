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


## Godot's default volumetric fog density (0.05 per metre) whited out the high preset past
## about 50 m at noon; the preset's own density is applied, light enough to keep the city.
func test_volumetric_fog_density_comes_from_the_preset() -> void:
	var s := _make(false)
	s.apply_preset("high")
	var env := Environment.new()
	s.apply_to_environment(env)
	var density := float(s.presets["high"]["volumetric_fog_density"])
	assert_bool(env.volumetric_fog_enabled).is_true()
	assert_float(env.volumetric_fog_density).is_equal_approx(density, 0.00001)
	# Under 10 % of the light lost over 50 m of haze.
	assert_float(exp(-density * 50.0)).is_greater(0.9)


func _button(index: int) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.button_index = index as JoyButton
	return b


func test_rebind_saves_and_a_fresh_start_applies_it() -> void:
	var s := _make(false)
	assert_str(s.rebind("horn", _button(JOY_BUTTON_DPAD_UP))).is_equal("")
	assert_str(Controls.binding_text("horn", true)).is_equal("D-pad up")
	assert_str(Controls.binding_text("horn", false)).is_equal("G")  # the key is untouched
	InputMap.load_from_project_settings()  # what a fresh start sees before Settings runs
	assert_str(Controls.binding_text("horn", true)).is_equal("L3")
	var again := _make(false)
	again.apply_bindings()
	assert_str(Controls.binding_text("horn", true)).is_equal("D-pad up")
	InputMap.load_from_project_settings()


func test_conflicting_rebind_is_refused_with_the_action_named() -> void:
	var s := _make(false)
	assert_str(s.rebind("horn", _button(JOY_BUTTON_RIGHT_SHOULDER))).is_equal("handbrake")
	assert_str(Controls.binding_text("horn", true)).is_equal("L3")
	assert_dict(s.binding_overrides).is_empty()
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	assert_str(s.rebind("horn", space)).is_equal("handbrake")
	assert_str(s.rebind("sprint", space)).is_equal("jump")  # on foot Space jumps
	InputMap.load_from_project_settings()


func test_reset_restores_defaults_and_forgets_the_file() -> void:
	var s := _make(false)
	s.rebind("camera_cycle", _button(JOY_BUTTON_DPAD_UP))
	s.reset_bindings()
	assert_str(Controls.binding_text("camera_cycle", true)).is_equal("D-pad down")
	var again := _make(false)
	assert_dict(again.binding_overrides).is_empty()


func test_stick_groups_and_unknown_entries_are_not_rebound() -> void:
	var s := _make(false)
	assert_str(s.rebind("move_left", _button(JOY_BUTTON_X))).is_not_empty()
	s.binding_overrides = {"no_such_action/pad": {"type": "button", "index": 2}, "horn/pad": {"type": "nonsense"}}
	s.apply_bindings()  # neither crashes nor binds
	assert_str(Controls.binding_text("horn", true)).is_equal("L3")
