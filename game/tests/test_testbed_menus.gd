extends GdUnitTestSuite
## The full testbed: D-pad presses that navigate menus must not reach the driving hotkeys
## (D-pad down cycles the camera, D-pad right the headlights), human report 2026-10-03. Also
## the review fixes that live in the testbed: the clock before the parked cars, and busted or
## wasted resetting the weapons with one banner timer. Starts at 10:00 (a parked-car hour block
## other than the default noon's).

const TESTBED := preload("res://scenes/play_testbed.tscn")

var _bed: Node


func before() -> void:
	_bed = TESTBED.instantiate()
	_bed.set("_start_in_car", true)
	_bed.set("_start_hour", 10.0)
	add_child(_bed)
	for i in range(600):
		await get_tree().process_frame
		var player: Variant = _bed.get("_player")
		if player != null and player.is_driving():
			break
	var started: Variant = _bed.get("_player")
	assert_bool(started != null and started.is_driving()).override_failure_message("the testbed never put the player in the car (600 frames)").is_true()


## Land whatever the streamer still has queued: queued meshes are outside the tree, and gdUnit
## counted them as orphans of every test here (about 1,100 per suite).
## Background builds still running (a test that moved the player far) land after a flush, so
## wait for them first (bounded).
func after_test() -> void:
	var streamer: Node = _bed.get("_streamer") if _bed != null else null
	if streamer != null and streamer.has_method("flush"):
		for i in range(600):
			if not streamer.call("is_busy"):
				break
			await get_tree().process_frame
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
	if radio != null and radio.rendering():
		push_warning("radio renders still running after 1200 frames; freeing the testbed anyway")
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


# --- review fixes (2026-10-06); last, since a catch takes the player out of the car ---


func test_parked_cars_fill_for_the_start_hour() -> void:
	var parked: ParkedCars = _bed.get("_parked")
	assert_float(parked.setup_hour).is_equal_approx(10.0, 0.01)  # not the default 12:00 first


func test_a_catch_resets_the_weapons_and_a_second_catch_keeps_its_banner() -> void:
	var shooter: Shooter = _bed.get("_shooter")
	var banner: Label = _bed.get("_banner")
	var wanted: Wanted = _bed.get("_wanted")
	wanted.config["banner_s"] = 0.4
	_bed.call("_caught", "busted")  # out of the car, so the wheel can open on foot
	await get_tree().process_frame
	shooter.wheel.open_wheel()
	assert_bool(shooter.wheel.is_open()).is_true()
	await get_tree().create_timer(0.25).timeout
	_bed.call("_caught", "wasted")
	assert_bool(shooter.wheel.is_open()).override_failure_message("the wheel stayed open through a catch").is_false()
	await get_tree().create_timer(0.25).timeout  # past the first banner's time, inside the second's
	assert_bool(banner.visible).override_failure_message("the first catch's timer hid the second banner").is_true()
	await get_tree().create_timer(0.35).timeout
	assert_bool(banner.visible).is_false()


## Human, 2026-10-06: on foot there was no way back from being stuck short of closing the game.
## Holding reset for the hold time takes the player to the start, standing on built ground.
func test_holding_reset_on_foot_goes_back_to_the_start() -> void:
	var player: Variant = _bed.get("_player")
	if player.is_driving():
		player.try_exit_vehicle()
		await get_tree().physics_frame
	var pack: MapPack = _bed.get("_pack")
	var start: Vector3 = pack.spawn_transform().origin
	var away := start + Vector3(400.0, 0.0, 300.0)
	player.global_position = away + Vector3.UP * 50.0
	player.velocity = Vector3.ZERO
	var half := Controls.hold_s() * 0.6
	var progress: float = _bed.call("_step_foot_reset", true, half)
	assert_float(progress).is_greater(0.0)
	assert_float(player.global_position.distance_to(start)).is_greater(100.0)
	_bed.call("_step_foot_reset", true, half)
	assert_float(Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()).is_less(0.5)
	# A long hold resets once; letting go arms it again.
	player.global_position = away + Vector3.UP * 50.0
	assert_float(_bed.call("_step_foot_reset", true, half)).is_equal(0.0)
	assert_float(player.global_position.distance_to(start)).is_greater(100.0)
	_bed.call("_step_foot_reset", false, half)
	_bed.call("_step_foot_reset", true, half)
	_bed.call("_step_foot_reset", true, half)
	for i in range(60):
		await get_tree().physics_frame
	assert_bool(player.is_on_floor()).override_failure_message("the player fell through the ground at the start").is_true()
	assert_float(absf(player.global_position.y - start.y)).is_less(3.0)
