extends GdUnitTestSuite
## The full testbed: D-pad presses that navigate menus must not reach the driving hotkeys
## (D-pad down cycles the camera, D-pad right the headlights), human report 2026-10-03.

const TESTBED := preload("res://scenes/play_testbed.tscn")

var _bed: Node


func before() -> void:
	_bed = TESTBED.instantiate()
	_bed.set("_start_in_car", true)
	add_child(_bed)
	for i in range(600):
		await get_tree().process_frame
		var player: Variant = _bed.get("_player")
		if player != null and player.is_driving():
			break


## Land whatever the streamer still has queued: queued meshes are outside the tree, and gdUnit
## counted them as orphans of every test here (about 1,100 per suite).
func after_test() -> void:
	var streamer: Node = _bed.get("_streamer") if _bed != null else null
	if streamer != null and streamer.has_method("flush"):
		streamer.flush()


func after() -> void:
	get_tree().paused = false
	if _bed == null:
		return
	# Freeing the testbed makes the chunk streamer block the main thread until its background
	# builds finish; on a two-core CI runner that wait never ended. Stop new work and let the
	# builds in flight finish over frames first.
	var streamer: Node = _bed.get("_streamer")
	if streamer != null:
		streamer.process_mode = Node.PROCESS_MODE_DISABLED
		var pending: Dictionary = streamer.get("_pending")
		for i in range(1200):
			if pending.is_empty() or _all_done(pending):
				break
			await get_tree().process_frame
	var radio: Radio = _bed.get("_radio")
	for i in range(1200):
		if radio == null or not radio.rendering():
			break
		await get_tree().process_frame
	_bed.queue_free()
	# Let anything the testbed left in flight wind down before the next suite: without this,
	# the next suite sometimes aborted on a worker thread touching /root (exit 134).
	for i in range(60):
		await get_tree().process_frame


func _all_done(pending: Dictionary) -> bool:
	for coord in pending:
		if not WorkerThreadPool.is_task_completed(pending[coord]["task"]):
			return false
	return true


func _press(button: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame


func test_player_is_driving() -> void:
	assert_bool(_bed.get("_player").is_driving()).is_true()


func test_dpad_down_in_play_cycles_the_camera() -> void:
	var cam: ChaseCamera = _bed.get("_camera")
	var before_mode := cam.mode
	await _press(JOY_BUTTON_DPAD_DOWN)
	assert_int(cam.mode).is_not_equal(before_mode)


func test_dpad_in_the_pause_menu_leaves_camera_and_lights_alone() -> void:
	var cam: ChaseCamera = _bed.get("_camera")
	var menu: PauseMenu = _bed.get("_pause_menu")
	await _press(JOY_BUTTON_START)
	assert_bool(menu.visible).is_true()
	var mode := cam.mode
	var lights: int = _bed.get("_headlights")
	for i in range(3):
		await _press(JOY_BUTTON_DPAD_DOWN)
		await _press(JOY_BUTTON_DPAD_UP)
		await _press(JOY_BUTTON_DPAD_RIGHT)  # the headlights button; on the first row it does nothing
	assert_int(cam.mode).override_failure_message("camera changed behind the pause menu").is_equal(mode)
	assert_int(_bed.get("_headlights")).override_failure_message("lights changed behind the pause menu").is_equal(lights)
	await _press(JOY_BUTTON_B)  # resume
	assert_bool(menu.visible).is_false()
	assert_int(cam.mode).override_failure_message("closing the menu changed the camera").is_equal(mode)


func _assert_dpad_leaves_driving_alone(where: String) -> void:
	var cam: ChaseCamera = _bed.get("_camera")
	var mode := cam.mode
	var lights: int = _bed.get("_headlights")
	for i in range(3):
		await _press(JOY_BUTTON_DPAD_DOWN)
		await _press(JOY_BUTTON_DPAD_UP)
		await _press(JOY_BUTTON_DPAD_RIGHT)  # the headlights button; on the first row it does nothing
	assert_int(cam.mode).override_failure_message("camera changed behind the %s" % where).is_equal(mode)
	assert_int(_bed.get("_headlights")).override_failure_message("lights changed behind the %s" % where).is_equal(lights)


func test_dpad_in_the_report_form_leaves_camera_and_lights_alone() -> void:
	var form: ReportForm = _bed.get("_report_form")
	var menu: PauseMenu = _bed.get("_pause_menu")
	menu.open()
	menu.report_requested.emit()  # what holding Menu does
	await get_tree().process_frame
	assert_bool(form.visible).is_true()
	await _assert_dpad_leaves_driving_alone("report form")
	# Typing in the description, then a D-pad press to finish.
	form._description.grab_focus()
	await _assert_dpad_leaves_driving_alone("report form while typing")
	form.close()
	await get_tree().process_frame
	menu.close()
	await get_tree().process_frame


func test_dpad_on_the_map_leaves_camera_and_lights_alone() -> void:
	var map: OverviewMap = _bed.get("_overview")
	map.open()
	await get_tree().process_frame
	await _assert_dpad_leaves_driving_alone("map")
	map.close()
	await get_tree().process_frame
