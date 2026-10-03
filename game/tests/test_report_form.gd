extends GdUnitTestSuite
## "Report a problem" driven by a controller alone, and the pause menu's ways into it.

const FORM_SCENE := preload("res://ui/report/report_form.tscn")
const PAUSE_SCENE := preload("res://ui/pause/pause_menu.tscn")

var _base: String
var _form: ReportForm


func before_test() -> void:
	_base = "user://tmp/form_reports_%d" % Time.get_ticks_usec()
	_form = auto_free(FORM_SCENE.instantiate())
	add_child(_form)
	_form.store = ReportStore.new(_base)
	var shot := Image.create(320, 200, false, Image.FORMAT_RGB8)
	shot.fill(Color(0.3, 0.3, 0.3))
	var place := Diagnostics.empty_place()
	place.merge({"x": 237.0, "z": 18.0, "mode": "car", "road": "Elgin Street"}, true)
	_form.open(shot, Diagnostics.collect(place, [], FrameTimes.new().stats()), ["log line"])
	await get_tree().process_frame


func after_test() -> void:
	get_tree().paused = false
	for row in ReportStore.new(_base).list():
		ReportStore.new(_base).delete(row["id"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_base))


func _press(button: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _go_to(row: String) -> void:
	for i in range(ReportForm.ROWS.size()):
		if ReportForm.ROWS[_form._selected] == row:
			return
		await _press(JOY_BUTTON_DPAD_DOWN)
	fail("could not reach row %s; stuck on %s" % [row, ReportForm.ROWS[_form._selected]])


func test_controller_sets_area_and_sends() -> void:
	assert_bool(get_tree().paused).is_true()
	await _go_to("area")
	await _press(JOY_BUTTON_DPAD_RIGHT)
	await _go_to("severity")
	await _press(JOY_BUTTON_DPAD_RIGHT)
	await _go_to("send")
	await _press(JOY_BUTTON_A)
	var rows := _form.store.list()
	assert_int(rows.size()).is_equal(1)
	var report := _form.store.load_report(rows[0]["id"])
	assert_str(report["area"]).is_equal("traffic")
	assert_str(report["severity"]).is_equal("blocks_play")
	assert_str(report["title"]).is_equal("Traffic: Elgin Street at x 237, z 18")
	assert_bool(report["has_screenshot"]).is_true()
	assert_str(_form.store.screenshot_path(rows[0]["id"])).is_not_empty()
	# Sending twice does not save a second copy.
	await _press(JOY_BUTTON_A)
	assert_int(_form.store.list().size()).is_equal(1)


func test_screenshot_can_be_left_out() -> void:
	await _press(JOY_BUTTON_DPAD_RIGHT)  # first row: screenshot included -> left out
	await _go_to("send")
	await _press(JOY_BUTTON_A)
	var id: String = _form.store.list()[0]["id"]
	assert_bool(_form.store.load_report(id)["has_screenshot"]).is_false()
	assert_str(_form.store.screenshot_path(id)).is_empty()


func test_b_leaves_a_text_field_then_closes_the_form() -> void:
	var closed := [false]
	_form.closed.connect(func() -> void: closed[0] = true)
	await _go_to("title")
	await _press(JOY_BUTTON_A)
	assert_bool(_form._title.has_focus()).is_true()
	await _press(JOY_BUTTON_B)
	assert_bool(_form._title.has_focus()).is_false()
	assert_bool(_form.visible).is_true()
	await _press(JOY_BUTTON_B)
	assert_bool(_form.visible).is_false()
	assert_bool(closed[0]).is_true()


func test_review_page_lists_what_will_be_sent() -> void:
	await _go_to("review")
	await _press(JOY_BUTTON_A)
	assert_int(_form._page).is_equal(ReportForm.Page.REVIEW)
	assert_str(_form._review_text.text).contains("\"diagnostics\"")
	assert_str(_form._review_text.text).contains("Elgin Street")
	await _press(JOY_BUTTON_B)
	assert_int(_form._page).is_equal(ReportForm.Page.MAIN)
	assert_bool(_form.visible).is_true()


func test_saved_reports_page_deletes() -> void:
	_form.send()
	await _go_to("queue")
	await _press(JOY_BUTTON_A)
	assert_int(_form._page).is_equal(ReportForm.Page.QUEUE)
	assert_str(_form._queue_list.text).contains("[queued]")
	for i in range(3):
		if _form._queue_actions()[_form._queue_action] == "Delete":
			break
		await _press(JOY_BUTTON_DPAD_RIGHT)
	await _press(JOY_BUTTON_A)
	assert_int(_form.store.list().size()).is_equal(0)


func test_holding_menu_opens_the_report_and_a_tap_does_not() -> void:
	_form.close()
	var menu: PauseMenu = auto_free(PAUSE_SCENE.instantiate())
	add_child(menu)
	var requested := [0]
	menu.report_requested.connect(func() -> void: requested[0] += 1)
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_START
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	assert_bool(menu.visible).is_true()
	# Headless runs draw nothing, so the frame itself is checked in the Mac run; the stats always exist.
	assert_dict(menu.captured_frame_stats).contains_keys(["avg_ms", "p99_ms", "seconds"])
	await get_tree().create_timer(PauseMenu.REPORT_HOLD_S + 0.2, true).timeout  # runs while paused
	assert_int(requested[0]).is_equal(1)
	ev = InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_START
	ev.pressed = false
	Input.parse_input_event(ev)
	await get_tree().process_frame
	# A tap: press and release at once closes the menu again and asks for nothing.
	menu.close()
	await _press(JOY_BUTTON_START)
	await get_tree().create_timer(PauseMenu.REPORT_HOLD_S + 0.2, true).timeout  # runs while paused
	assert_int(requested[0]).is_equal(1)
	menu.close()


func test_report_row_in_the_pause_menu() -> void:
	_form.close()
	var menu: PauseMenu = auto_free(PAUSE_SCENE.instantiate())
	add_child(menu)
	var requested := [0]
	menu.report_requested.connect(func() -> void: requested[0] += 1)
	menu.open()
	await get_tree().process_frame
	for i in range(PauseMenu.REPORT_ROW):
		await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)
	assert_int(requested[0]).is_equal(1)
	menu.close()
