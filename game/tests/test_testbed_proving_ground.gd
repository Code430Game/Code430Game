extends GdUnitTestSuite
## The testbed on the proving ground (add-proving-ground): `--pack` starts the player on the
## pack's own start line, and the lap readout appears on the loop, starts at the line and
## hides off the loop.

const TESTBED := preload("res://scenes/play_testbed.tscn")

var _bed: Node


func before() -> void:
	_bed = TESTBED.instantiate()
	_bed.set("_pack_id", "code430.proving-ground")
	_bed.set("_start_in_car", true)
	_bed.set("_mute", true)
	_bed.set("_traffic_cap", 0)
	_bed.set("_peds_cap", 0)
	add_child(_bed)
	var until := Time.get_ticks_msec() + 180000  # the map loads on a thread under the loading screen
	while not _bed.get("map_loaded") and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	for i in range(600):
		await get_tree().process_frame
		var player: Variant = _bed.get("_player")
		if player != null and player.is_driving():
			break
	var started: Variant = _bed.get("_player")
	assert_bool(started != null and started.is_driving()).override_failure_message("the testbed never put the player in the car (600 frames)").is_true()


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
	for i in range(60):
		await get_tree().process_frame


func _all_done(pending: Dictionary) -> bool:
	for coord in pending:
		if not WorkerThreadPool.is_task_completed(pending[coord]["task"]):
			return false
	return true


func _car() -> VehicleBody3D:
	return _bed.get("_car")


func _lap_label() -> Label:
	return _bed.get("_lap_label")


## Moves the car to (x, z) at road height and lets a frame pass.
func _place(x: float, z: float) -> void:
	var car := _car()
	car.linear_velocity = Vector3.ZERO
	car.global_position = Vector3(x, car.global_position.y, z)
	await get_tree().process_frame
	await get_tree().process_frame


func test_pack_flag_starts_on_the_proving_ground_start_line() -> void:
	var pack: MapPack = _bed.get("_pack")
	assert_str(str(pack.manifest.get("id", ""))).is_equal("code430.proving-ground")
	var car := _car()
	assert_float(car.global_position.x).is_equal_approx(-1.75, 2.0)
	assert_float(car.global_position.z).is_equal_approx(-340.0, 2.0)


func test_lap_readout_shows_on_the_loop_starts_at_the_line_and_hides_off_it() -> void:
	var label := _lap_label()
	assert_object(label).is_not_null()
	await _place(-1.75, -320.0)
	assert_bool(label.visible).is_true()
	assert_str(label.text).starts_with("LAP  --:--.-")
	# Across the start line at z = -180, heading south, in small steps like a car would.
	for z in range(-200, -150, 5):
		await _place(-6.0, float(z))
	assert_str(label.text).starts_with("LAP  0:0")
	# Into the main city grid, off every loop road: the readout hides and the lap resets.
	await _place(-320.0, -270.0)
	assert_bool(label.visible).is_false()
	var timer: LapTimer = _bed.get("_lap")
	assert_float(timer.current_s).is_equal(-1.0)
