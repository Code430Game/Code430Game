extends GdUnitTestSuite
## Player registry, config, and vehicle entry rules.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const CAR_SCENE := preload("res://actors/vehicles/placeholder_car.tscn")


func after_test() -> void:
	Players.clear()


func test_registry_by_peer_id() -> void:
	var a := Node.new()
	var b := Node.new()
	auto_free(a)
	auto_free(b)
	Players.register(1, a)
	Players.register(7, b)
	assert_object(Players.local()).is_same(a)
	assert_int(Players.all().size()).is_equal(2)
	assert_object(Players.all()[7]).is_same(b)
	Players.unregister(1)
	assert_object(Players.local()).is_null()


func test_config_jump_velocity_reaches_height() -> void:
	var cfg := PlayerConfig.new()
	cfg.jump_height_m = 1.2
	var v := cfg.jump_velocity(9.8)
	assert_float(v * v / (2.0 * 9.8)).is_equal_approx(1.2, 1e-6)


func test_player_registers_itself_and_controls_body() -> void:
	var player: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(player)
	assert_object(Players.local()).is_same(player)
	assert_object(Players.local_controlled_body()).is_same(player)
	assert_bool(player.is_driving()).is_false()


func test_enter_and_exit_vehicle_on_flat_ground() -> void:
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var car: VehicleBody3D = auto_free(CAR_SCENE.instantiate())
	add_child(car)
	car.global_position = Vector3(0, 0.6, 0)
	var player: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(player)
	player.global_position = Vector3(1.5, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_object(player.nearest_vehicle()).is_same(car)
	player.global_position = Vector3(6.0, 0.0, 0.0)
	assert_object(player.nearest_vehicle()).is_null()
	player.enter_vehicle(car)
	assert_bool(player.is_driving()).is_true()
	assert_int(car.driver_peer_id).is_equal(Players.LOCAL_PEER_ID)
	assert_object(Players.local_controlled_body()).is_same(car)
	await get_tree().physics_frame
	assert_bool(player.try_exit_vehicle()).is_true()
	assert_bool(player.is_driving()).is_false()
	assert_int(car.driver_peer_id).is_equal(0)
	var expected := car.global_position - car.global_basis.x * player.config.exit_side_offset_m
	assert_float(player.global_position.distance_to(Vector3(expected.x, 0.05, expected.z))).is_less(0.2)


func test_exit_refused_at_speed() -> void:
	var car: VehicleBody3D = auto_free(CAR_SCENE.instantiate())
	add_child(car)
	var player: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(player)
	player.enter_vehicle(car)
	car.linear_velocity = Vector3(0, 0, -10)
	assert_bool(player.try_exit_vehicle()).is_false()
	assert_bool(player.is_driving()).is_true()
