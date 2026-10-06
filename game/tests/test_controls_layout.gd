extends GdUnitTestSuite
## update-controls-layout 1.2: hold to reset, look behind, the horn.

const CAR := preload("res://actors/vehicles/placeholder_car.tscn")


func _car() -> VehicleBody3D:
	var car: VehicleBody3D = auto_free(CAR.instantiate())
	add_child(car)
	return car


func test_a_tap_never_resets_and_a_hold_resets_once() -> void:
	var car := _car()
	var resets := [0]
	car.recover_callback = func(_c: Node) -> void: resets[0] += 1
	for i in range(int(Controls.data()["tap_s"] * 60.0)):  # a tap: looks behind, no reset
		car._step_reset_hold(true, 1.0 / 60.0)
	car._step_reset_hold(false, 1.0 / 60.0)
	assert_int(resets[0]).is_equal(0)
	assert_float(car.reset_progress()).is_equal(0.0)
	for i in range(30):
		car._step_reset_hold(true, 1.0 / 60.0)
	assert_float(car.reset_progress()).is_between(0.4, 0.6)  # the HUD ring half full
	for i in range(150):  # held well past the hold time: one reset
		car._step_reset_hold(true, 1.0 / 60.0)
	assert_int(resets[0]).is_equal(1)
	assert_float(car.reset_progress()).is_equal(0.0)
	car._step_reset_hold(false, 1.0 / 60.0)
	for i in range(70):
		car._step_reset_hold(true, 1.0 / 60.0)
	assert_int(resets[0]).is_equal(2)  # a fresh hold resets again


func test_handbrake_input_never_resets() -> void:
	var car := _car()
	var resets := [0]
	car.recover_callback = func(_c: Node) -> void: resets[0] += 1
	car.driver_peer_id = Players.LOCAL_PEER_ID
	Input.action_press("handbrake")
	for i in range(120):
		await get_tree().physics_frame
	Input.action_release("handbrake")
	assert_int(resets[0]).is_equal(0)


func test_look_behind_puts_the_chase_camera_in_front_of_the_car() -> void:
	var car := _car()
	var cam: ChaseCamera = auto_free(ChaseCamera.new())
	add_child(cam)
	cam.target = car
	await get_tree().process_frame
	var nose := -car.global_basis.z
	cam.look_behind = true
	await get_tree().process_frame
	assert_float((cam.global_position - car.global_position).normalized().dot(nose)).is_greater(0.8)
	cam.look_behind = false
	await get_tree().process_frame
	assert_float((cam.global_position - car.global_position).normalized().dot(nose)).is_less(-0.8)


func test_horn_sounds_two_tones_and_releases() -> void:
	var peak := 0.0
	for i in range(2000):
		peak = maxf(peak, absf(Horn.sample(TAU * Horn.LOW_HZ * i / Synth.MIX_RATE, TAU * Horn.HIGH_HZ * i / Synth.MIX_RATE)))
	assert_float(peak).is_equal_approx(0.5, 0.001)
	var horn: Horn = auto_free(Horn.new())
	add_child(horn)
	await get_tree().process_frame
	assert_bool(horn.audible()).is_false()
	horn.sounding = true
	await get_tree().process_frame
	assert_bool(horn.audible()).is_true()


func test_only_the_driver_holding_horn_sounds_it() -> void:
	var car := _car()
	var va := VehicleAudio.new()
	va.car = car
	car.add_child(va)
	await get_tree().process_frame
	assert_object(va.horn.get_parent()).is_same(car)  # heard from the car
	Input.action_press("horn")
	await get_tree().process_frame
	assert_bool(va.horn.sounding).is_false()  # nobody drives
	car.driver_peer_id = Players.LOCAL_PEER_ID
	await get_tree().process_frame
	assert_bool(va.horn.sounding).is_true()
	Input.action_release("horn")
	await get_tree().process_frame
	assert_bool(va.horn.sounding).is_false()


func test_the_chase_camera_stays_under_a_ceiling() -> void:
	# A slab 2.5 m over the car, as in a garage (#43): the camera must not rise through it.
	var car := _car()
	car.freeze = true
	car.global_position = Vector3(0, 0.5, 0)
	var ceiling: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.3, 60)
	shape.shape = box
	ceiling.add_child(shape)
	add_child(ceiling)
	ceiling.global_position = Vector3(0, 3.0, 0)
	var cam: ChaseCamera = auto_free(ChaseCamera.new())
	add_child(cam)
	cam.target = car
	for i in range(30):
		await get_tree().physics_frame
		await get_tree().process_frame
	assert_float(cam.global_position.y).is_less(3.0 - 0.15)


func test_the_chase_camera_stays_under_a_ceiling_edge() -> void:
	# The ceiling ends just behind the car, as at an opening over a garage ramp (#59): the
	# straight line to the camera slips past the edge, but the camera must not sit up there
	# looking at both sides of the slab.
	var car := _car()
	car.freeze = true
	car.global_position = Vector3(0, 0.5, 0)
	var ceiling: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.3, 34.5)  # z from -30 to 4.5
	shape.shape = box
	ceiling.add_child(shape)
	add_child(ceiling)
	ceiling.global_position = Vector3(0, 3.0, -12.75)
	var cam: ChaseCamera = auto_free(ChaseCamera.new())
	add_child(cam)
	cam.target = car
	for i in range(30):
		await get_tree().physics_frame
		await get_tree().process_frame
	assert_float(cam.global_position.y).is_less(3.0 - 0.15)
