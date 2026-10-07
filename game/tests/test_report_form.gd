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
	assert_str(report["title"]).is_equal("Report: Traffic · Blocks play · Elgin Street (x 237, z 18)")
	assert_str(report["reporter_id"]).is_equal("")
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


func _key(keycode: Key, shift: bool = false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.shift_pressed = shift
		ev.pressed = pressed
		if pressed and keycode >= KEY_A and keycode <= KEY_Z:
			ev.unicode = keycode + 32  # lower case letter
		Input.parse_input_event(ev)
		await get_tree().process_frame


func test_typing_ends_with_enter_or_b_and_survives_dpad_and_a() -> void:
	var closed := [false]
	_form.closed.connect(func() -> void: closed[0] = true)
	await _go_to("description")
	await _press(JOY_BUTTON_A)
	assert_bool(_form._description.has_focus()).is_true()
	await _key(KEY_M)  # the map key types an m, nothing else happens
	await _key(KEY_ENTER)
	assert_bool(_form._description.has_focus()).override_failure_message("Enter did not end typing").is_false()
	assert_str(_form._description.text).is_equal("m")
	await _press(JOY_BUTTON_A)
	assert_bool(_form._description.has_focus()).is_true()
	# The D-pad and A drive the Deck's on-screen keyboard: they must not end typing.
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_DPAD_RIGHT)
	await _press(JOY_BUTTON_A)
	assert_bool(_form._description.has_focus()).override_failure_message("D-pad or A ended typing").is_true()
	await _press(JOY_BUTTON_B)
	assert_bool(_form._description.has_focus()).override_failure_message("B did not end typing").is_false()
	assert_bool(_form.visible).is_true()
	await _press(JOY_BUTTON_B)
	assert_bool(_form.visible).is_false()
	assert_bool(closed[0]).is_true()


func test_reporter_id_is_only_sent_when_chosen() -> void:
	await _go_to("reporter")
	await _press(JOY_BUTTON_DPAD_RIGHT)
	await _go_to("send")
	await _press(JOY_BUTTON_A)
	var report := _form.store.load_report(_form.store.list()[0]["id"])
	assert_str(report["reporter_id"]).is_equal(ReportStore.reporter_id())


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
	assert_str(_form.queue_text()).contains("[queued]")
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


## Quick tags picked with the D-pad and A; a report with tags and no text can be sent.
func test_tags_are_picked_with_the_controller_and_sent_without_text() -> void:
	await _go_to("tags")
	await _press(JOY_BUTTON_DPAD_RIGHT)  # cursor to the second tag, "Stuck"
	await _press(JOY_BUTTON_A)
	for i in range(3):
		await _press(JOY_BUTTON_DPAD_RIGHT)  # on to "Police"
	await _press(JOY_BUTTON_A)
	assert_array(_form.picked_tags()).is_equal(["stuck", "police"])
	await _press(JOY_BUTTON_A)  # A again turns "Police" off
	assert_array(_form.picked_tags()).is_equal(["stuck"])
	await _press(JOY_BUTTON_A)
	assert_str(_form._title.text).ends_with("Stuck, Police")
	await _go_to("send")
	await _press(JOY_BUTTON_A)
	var rows := _form.store.list()
	assert_int(rows.size()).is_equal(1)
	var report := _form.store.load_report(rows[0]["id"])
	assert_array(report["tags"]).is_equal(["stuck", "police"])
	assert_str(report["description"]).is_equal("")


## The tags row made the form taller than the Deck's 800 px screen once; it must fit with room.
func test_the_form_fits_a_deck_screen() -> void:
	await get_tree().process_frame
	assert_float(_form._panel.get_combined_minimum_size().y).is_less_equal(780.0)


func test_a_click_on_a_chip_toggles_its_tag() -> void:
	var chip: Button = _form._tag_chips[0]
	chip.pressed.emit()
	assert_array(_form.picked_tags()).is_equal(["looks_wrong"])
	assert_bool(chip.button_pressed).is_true()
	assert_str(ReportForm.ROWS[_form._selected]).is_equal("tags")
	chip.pressed.emit()
	assert_array(_form.picked_tags()).is_empty()
	# A fresh open clears the tags.
	_form.open(null, {}, [])
	assert_array(_form.picked_tags()).is_empty()


class CountingStore:
	extends ReportStore
	var list_calls: int = 0

	func list() -> Array:
		list_calls += 1
		return super.list()


func test_navigation_does_not_rescan_saved_reports() -> void:
	# Review fix: every Up/Down re-read and parsed every saved report from disk.
	var counting := CountingStore.new(_base)
	_form.store = counting
	var shot := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var place := Diagnostics.empty_place()
	_form.open(shot, Diagnostics.collect(place, [], FrameTimes.new().stats()), [])
	await get_tree().process_frame
	var after_open := counting.list_calls
	assert_int(after_open).is_greater_equal(1)
	for i in range(4):
		await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_DPAD_RIGHT)
	await _press(JOY_BUTTON_DPAD_LEFT)
	assert_int(counting.list_calls).is_equal(after_open)
