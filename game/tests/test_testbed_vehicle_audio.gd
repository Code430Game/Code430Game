extends GdUnitTestSuite
## The full testbed: the engine sounds whenever the local player drives, after getting out and
## back in, and in a car taken later (human report 2026-10-03: the engine did not resume).

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


func after() -> void:
	get_tree().paused = false
	if _bed == null:
		return
	# See test_testbed_menus.gd: let the streamer's builds finish before freeing.
	var streamer: Node = _bed.get("_streamer")
	if streamer != null:
		streamer.process_mode = Node.PROCESS_MODE_DISABLED
		var pending: Dictionary = streamer.get("_pending")
		for i in range(1200):
			var done := true
			for coord in pending:
				done = done and WorkerThreadPool.is_task_completed(pending[coord]["task"])
			if done:
				break
			await get_tree().process_frame
	var radio: Radio = _bed.get("_radio")
	for i in range(1200):
		if radio == null or not radio.rendering():
			break
		await get_tree().process_frame
	_bed.queue_free()
	await get_tree().process_frame


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## The engine voice for whatever car the local player drives: running, and its player playing.
func _engine_audible() -> bool:
	var va: VehicleAudio = _bed.get("_vehicle_audio")
	var player: Player = _bed.get("_player")
	if va == null or player == null or not player.is_driving() or va.car != player.vehicle:
		return false
	return va.engine_running() and va.get("_engine").playing


func _get_out() -> void:
	var player: Player = _bed.get("_player")
	var car: VehicleBody3D = player.vehicle
	car.linear_velocity = Vector3.ZERO
	assert_bool(player.try_exit_vehicle()).override_failure_message("could not get out").is_true()
	await _frames(30)  # long enough for the engine generator to run dry


func test_engine_is_audible_at_the_start() -> void:
	await _frames(5)
	assert_bool(_engine_audible()).is_true()


func test_engine_resumes_after_getting_back_into_the_same_car() -> void:
	var player: Player = _bed.get("_player")
	var car: VehicleBody3D = player.vehicle
	await _get_out()
	player.enter_vehicle(car)
	await _frames(5)
	assert_bool(_engine_audible()).override_failure_message("silent after getting back in").is_true()


func test_engine_sounds_in_another_car() -> void:
	var player: Player = _bed.get("_player")
	await _get_out()
	var other: VehicleBody3D = TrafficManager.DRIVABLE_CAR_SCENE.instantiate()
	_bed.add_child(other)
	other.global_transform = player.global_transform.translated(Vector3(0.0, 0.5, 6.0))
	player.enter_vehicle(other)
	await _frames(5)
	assert_bool(_engine_audible()).override_failure_message("silent in a different car").is_true()
