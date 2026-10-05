extends GdUnitTestSuite
## The pause menu must close on A (accept) and B (cancel) from a gamepad while the tree is paused.

const PAUSE_SCENE := preload("res://ui/pause/pause_menu.tscn")


func after_test() -> void:
	get_tree().paused = false


func _joy(button: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)


func test_a_resumes_and_b_resumes() -> void:
	var menu: PauseMenu = auto_free(PAUSE_SCENE.instantiate())
	add_child(menu)
	menu.open()
	await get_tree().process_frame
	assert_bool(get_tree().paused).is_true()
	_joy(JOY_BUTTON_A, true)
	await get_tree().process_frame
	_joy(JOY_BUTTON_A, false)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(menu.visible).override_failure_message("A did not resume").is_false()
	assert_bool(get_tree().paused).is_false()
	menu.open()
	await get_tree().process_frame
	_joy(JOY_BUTTON_B, true)
	await get_tree().process_frame
	_joy(JOY_BUTTON_B, false)
	await get_tree().process_frame
	assert_bool(menu.visible).override_failure_message("B did not resume").is_false()


var _settings_path_before: String


func before_test() -> void:
	_settings_path_before = Settings.settings_path
	Settings.settings_path = "user://test_pause_settings_%d.cfg" % Time.get_ticks_usec()


func _restore_settings() -> void:
	if FileAccess.file_exists(Settings.settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.settings_path))
	Settings.settings_path = _settings_path_before
	Settings.binding_overrides = {}
	InputMap.load_from_project_settings()


func _press(button: int) -> void:
	_joy(button, true)
	await get_tree().process_frame
	_joy(button, false)
	await get_tree().process_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _open() -> PauseMenu:
	var menu: PauseMenu = auto_free(PAUSE_SCENE.instantiate())
	add_child(menu)
	menu.open()
	await get_tree().process_frame
	return menu


func _row_named(menu: PauseMenu, label: String) -> int:
	var rows := menu.rows(PauseMenu.CONTROLS_TAB)
	for i in range(rows.size()):
		if str((rows[i] as Button).get_meta("text", "")) == label:
			return i
	return -1


func test_lb_rb_and_q_e_cycle_the_tabs() -> void:
	var menu := await _open()
	assert_int(menu.tab).is_equal(PauseMenu.GAME_TAB)
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	assert_int(menu.tab).is_equal(PauseMenu.COOP_TAB)
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	assert_int(menu.tab).is_equal(PauseMenu.CONTROLS_TAB)
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	assert_int(menu.tab).is_equal(PauseMenu.SETTINGS_TAB)  # wraps round
	await _key(KEY_E)
	assert_int(menu.tab).is_equal(PauseMenu.GAME_TAB)
	await _key(KEY_Q)
	assert_int(menu.tab).is_equal(PauseMenu.SETTINGS_TAB)
	menu.close()
	_restore_settings()


func test_controls_tab_shows_the_layout_of_the_device_in_use() -> void:
	var menu := await _open()
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	await _press(JOY_BUTTON_RIGHT_SHOULDER)  # past Co-op to Controls
	var horn: Button = menu.rows(PauseMenu.CONTROLS_TAB)[_row_named(menu, "horn")]
	assert_str((horn.get_meta("binding") as Label).text).is_equal("L3")
	var reset: Button = menu.rows(PauseMenu.CONTROLS_TAB)[_row_named(menu, "reset a stuck car")]
	assert_str((reset.get_meta("binding") as Label).text).is_equal("hold R3")
	await _key(KEY_DOWN)  # touching the keyboard switches the list
	assert_bool(menu.showing_pad).is_false()
	horn = menu.rows(PauseMenu.CONTROLS_TAB)[_row_named(menu, "horn")]
	assert_str((horn.get_meta("binding") as Label).text).is_equal("G")
	assert_int(_row_named(menu, "aim")).is_equal(-1)  # reserved for combat: not shown yet
	menu.close()
	_restore_settings()


func _select(menu: PauseMenu, row: int) -> void:
	while menu.selected_row() != row:
		await _press(JOY_BUTTON_DPAD_DOWN)


func test_rebinding_with_a_controller_alone_and_conflicts_refused() -> void:
	var menu := await _open()
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	await _press(JOY_BUTTON_RIGHT_SHOULDER)  # past Co-op to Controls
	await _select(menu, _row_named(menu, "horn"))
	await _press(JOY_BUTTON_A)
	assert_str(menu.capturing).is_equal("horn")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)  # the handbrake's button: refused, and no tab change
	assert_int(menu.tab).is_equal(PauseMenu.CONTROLS_TAB)
	assert_str(menu._controls_note.text).contains("handbrake")
	assert_str(Controls.binding_text("horn", true)).is_equal("L3")
	await _press(JOY_BUTTON_A)
	await _press(JOY_BUTTON_DPAD_UP)  # free while driving
	assert_str(Controls.binding_text("horn", true)).is_equal("D-pad up")
	assert_str(menu.capturing).is_equal("")
	assert_dict(Settings.binding_overrides).contains_keys(["horn/pad"])
	await _press(JOY_BUTTON_A)
	await _press(JOY_BUTTON_START)  # Menu cancels a capture without closing the menu
	assert_bool(menu.visible).is_true()
	assert_str(Controls.binding_text("horn", true)).is_equal("D-pad up")
	await _select(menu, menu.rows(PauseMenu.CONTROLS_TAB).size() - 1)
	await _press(JOY_BUTTON_A)  # reset to defaults
	assert_str(Controls.binding_text("horn", true)).is_equal("L3")
	assert_dict(Settings.binding_overrides).is_empty()
	menu.close()
	_restore_settings()


func test_nothing_runs_off_a_1280_by_800_screen() -> void:
	# The Deck's screen; headless runs have a tiny window, so the menu is laid out in a viewport of that size.
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = Vector2i(1280, 800)
	add_child(vp)
	var menu: PauseMenu = PAUSE_SCENE.instantiate()
	vp.add_child(menu)
	menu.open()
	await get_tree().process_frame
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 800))
	for t in range(PauseMenu.TABS.size()):
		menu.show_tab(t)
		await get_tree().process_frame
		var panel: Control = menu.get_node("Panel")
		assert_bool(screen.encloses(panel.get_global_rect())).override_failure_message(
			"%s tab: panel %s leaves the screen" % [PauseMenu.TABS[t], panel.get_global_rect()]).is_true()
	menu.show_tab(PauseMenu.CONTROLS_TAB)
	await get_tree().process_frame
	menu._move(-1)  # wraps to the last row, the farthest down the list
	for i in range(3):
		await get_tree().process_frame
	var last: Button = menu.rows(PauseMenu.CONTROLS_TAB)[-1]
	assert_bool(menu._controls_scroll.get_global_rect().grow(1.0).encloses(last.get_global_rect())).override_failure_message(
		"the last controls row is scrolled out of view").is_true()
	assert_bool(screen.encloses(last.get_global_rect())).is_true()
	menu.close()
	_restore_settings()


func test_options_and_settings_change_with_left_and_right() -> void:
	var menu := await _open()
	var before := ContentMode.mode_name()
	menu.show_tab(PauseMenu.OPTIONS_TAB)
	await _press(JOY_BUTTON_DPAD_RIGHT)
	assert_str(ContentMode.mode_name()).is_not_equal(before)
	await _press(JOY_BUTTON_DPAD_LEFT)
	assert_str(ContentMode.mode_name()).is_equal(before)
	var preset_before := Settings.preset_override
	menu.show_tab(PauseMenu.SETTINGS_TAB)
	await _press(JOY_BUTTON_DPAD_RIGHT)
	assert_str(Settings.preset_override).is_not_equal(preset_before)
	await _press(JOY_BUTTON_DPAD_LEFT)
	assert_str(Settings.preset_override).is_equal(preset_before)
	menu.close()
	_restore_settings()


func test_co_op_has_its_own_tab_and_join_still_focuses_the_address() -> void:
	var menu := await _open()
	var joined := [""]
	menu.join_requested.connect(func(a: String) -> void: joined[0] = a)
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	assert_int(menu.tab).is_equal(PauseMenu.COOP_TAB)
	assert_int(menu.rows(PauseMenu.COOP_TAB).size()).is_equal(2)
	assert_int(menu.rows(PauseMenu.GAME_TAB).size()).is_equal(4)  # resume, character, report, quit
	await _press(JOY_BUTTON_DPAD_DOWN)
	assert_int(menu.selected_row()).is_equal(PauseMenu.JOIN_ROW)
	await _press(JOY_BUTTON_DPAD_RIGHT)
	assert_bool(menu._address.has_focus()).is_true()
	menu._address.release_focus()
	await _press(JOY_BUTTON_A)
	assert_str(joined[0]).is_equal("127.0.0.1")
	menu.close()
	_restore_settings()
