extends GdUnitTestSuite
## update-menu-design: one menu theme from data, an accent that follows the tone, text that
## reads on the Deck, and selections that stay inside the panel's padding.

const PAUSE_SCENE := preload("res://ui/pause/pause_menu.tscn")

var _mode_before: String
var _settings_path_before: String


func before_test() -> void:
	_mode_before = ContentMode.current
	_settings_path_before = Settings.settings_path
	Settings.settings_path = "user://test_menu_theme_%d.cfg" % Time.get_ticks_usec()


func after_test() -> void:
	ContentMode.set_mode(_mode_before, false)
	MenuTheme.refresh_accent()
	get_tree().paused = false
	if FileAccess.file_exists(Settings.settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.settings_path))
	Settings.settings_path = _settings_path_before


func test_the_theme_takes_its_values_from_the_data() -> void:
	var data := MenuTheme.load_data()
	data["spacing"]["outer_padding"] = 31
	data["fonts"]["small"] = 15
	data["colors"]["panel"] = "#102030"
	var t := MenuTheme.build(data)
	var panel := t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	assert_float(panel.content_margin_left).is_equal(31.0)
	assert_float(panel.content_margin_bottom).is_equal(31.0)
	assert_bool(panel.bg_color.is_equal_approx(Color.html("#102030"))).is_true()
	assert_int(t.get_font_size("font_size", MenuTheme.KEY_CAP)).is_equal(15)
	assert_int(panel.shadow_size).is_greater(0)
	assert_int(panel.border_width_left).is_greater(0)
	# The selected row's left bar fits inside the row's left padding, so text doesn't shift.
	var plain := t.get_stylebox("normal", MenuTheme.ROW) as StyleBoxFlat
	var sel := t.get_stylebox("normal", MenuTheme.ROW_SELECTED) as StyleBoxFlat
	assert_float(sel.content_margin_left).is_equal(plain.content_margin_left)
	assert_float(plain.content_margin_left).is_greater(float(sel.border_width_left))


func test_the_accent_follows_the_tone() -> void:
	for id: String in ["clean", "gritty", "dystopia"]:
		ContentMode.set_mode(id, false)
		var t := MenuTheme.theme()
		var accent := ContentMode.hud_accent()
		var sel := t.get_stylebox("normal", MenuTheme.ROW_SELECTED) as StyleBoxFlat
		var tab := t.get_stylebox("pressed", MenuTheme.TAB) as StyleBoxFlat
		assert_bool(sel.border_color.is_equal_approx(accent)).override_failure_message("%s: row bar %s, accent %s" % [id, sel.border_color, accent]).is_true()
		assert_bool(tab.bg_color.is_equal_approx(accent)).override_failure_message("%s: active tab" % id).is_true()


func test_text_reads_against_the_panel_in_every_tone() -> void:
	var data := MenuTheme.load_data()
	var panel := MenuTheme.color(data, "panel")
	panel.a = 1.0
	assert_int(int(MenuTheme.num(data, "fonts", "body", 0))).is_greater_equal(18)
	assert_int(int(MenuTheme.num(data, "fonts", "row", 0))).is_greater_equal(18)
	for key in ["text", "muted"]:
		var ratio := MenuTheme.contrast(MenuTheme.color(data, key), panel)
		assert_float(ratio).override_failure_message("%s on the panel: %.2f" % [key, ratio]).is_greater_equal(4.5)
	var alpha := MenuTheme.num(data, "shape", "selection_alpha", 0.24)
	for id: String in ["clean", "gritty", "dystopia"]:
		ContentMode.set_mode(id, false)
		var accent := ContentMode.hud_accent()
		var fill := panel.lerp(accent, alpha)
		var on_row := MenuTheme.contrast(MenuTheme.color(data, "selected_text"), fill)
		assert_float(on_row).override_failure_message("%s: selected row %.2f" % [id, on_row]).is_greater_equal(4.5)
		var heading := MenuTheme.contrast(accent, panel)
		assert_float(heading).override_failure_message("%s: accent heading %.2f" % [id, heading]).is_greater_equal(4.5)
		var on_tab := MenuTheme.contrast(MenuTheme.color(data, "tab_active_text"), accent)
		assert_float(on_tab).override_failure_message("%s: active tab %.2f" % [id, on_tab]).is_greater_equal(4.5)


func test_every_selection_stays_inside_the_panel_padding() -> void:
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = Vector2i(1280, 800)
	add_child(vp)
	var menu: PauseMenu = PAUSE_SCENE.instantiate()
	vp.add_child(menu)
	menu.open()
	await get_tree().process_frame
	var panel: Control = menu.get_node("Panel")
	var pad := MenuTheme.num(MenuTheme.theme().get_meta("data", {}), "spacing", "outer_padding", 24)
	var inner := panel.get_global_rect().grow(-pad + 0.5)
	for t in range(PauseMenu.TABS.size()):
		menu.show_tab(t)
		await get_tree().process_frame
		var rows := menu.rows(t)
		for i in range(mini(rows.size(), 6)):
			while menu.selected_row() != i:
				menu._move(1)
			await get_tree().process_frame
			await get_tree().process_frame
			var b: Button = rows[i]
			assert_str(b.theme_type_variation).is_equal(MenuTheme.ROW_SELECTED)
			assert_bool(b.text.begins_with(">")).override_failure_message("a text marker is back").is_false()
			assert_bool(inner.encloses(b.get_global_rect())).override_failure_message(
				"%s row %d: %s outside the padding %s" % [PauseMenu.TABS[t], i, b.get_global_rect(), inner]).is_true()
			for j in range(rows.size()):
				if j != i:
					assert_str((rows[j] as Button).theme_type_variation).is_equal(MenuTheme.ROW)
	menu.show_tab(PauseMenu.CONTROLS_TAB)
	assert_str(menu.hint_text()).contains("rebind")
	menu.close()
	await get_tree().process_frame  # rows the Controls tab rebuilt are freed at the frame's end
	menu.free()
