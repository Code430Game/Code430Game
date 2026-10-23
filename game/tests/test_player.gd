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


func test_player_wades_on_a_water_floor_and_cars_do_not() -> void:
	# A flat water surface at y = 0 as the mesh; its wading floor sits WADE_DEPTH_M below it.
	var tris := RoadMeshBuilder.ChunkTriangles.new()
	tris.add_quad(Vector3(-50, 0, -50), Vector3(50, 0, -50), Vector3(-50, 0, 50), Vector3(50, 0, 50), Color.BLUE)
	var floor_body: StaticBody3D = auto_free(MapPack.build_water_floor(tris.to_mesh()))
	add_child(floor_body)
	assert_int(floor_body.collision_layer).is_equal(MapPack.WATER_LAYER_BIT)
	assert_bool(floor_body.is_in_group("water")).is_true()
	var player: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(player)
	player.global_position = Vector3(0, 0.5, 0)
	for i in range(40):
		await get_tree().physics_frame
	assert_bool(player.is_on_floor()).is_true()
	assert_float(player.global_position.y).is_equal_approx(-MapPack.WADE_DEPTH_M, 0.1)
	assert_bool(player.is_wading()).is_true()
	# The car's default mask is the world layer only, so it falls through water.
	var car: VehicleBody3D = auto_free(CAR_SCENE.instantiate())
	add_child(car)
	car.global_position = Vector3(10, 0.5, 0)
	for i in range(40):
		await get_tree().physics_frame
	assert_float(car.global_position.y).is_less(-MapPack.WADE_DEPTH_M - 0.5)


## A floor at y 0 and a box `h` tall whose near face is at z -2.
func _floor_and_step(h: float) -> void:
	for spec in [[Vector3(200, 1, 200), Vector3(0, -0.5, 0)], [Vector3(10, h, 10), Vector3(0, h * 0.5, -7)]]:
		var body: StaticBody3D = auto_free(StaticBody3D.new())
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[0]
		shape.shape = box
		body.add_child(shape)
		body.position = spec[1]
		add_child(body)


func _walk_forward(player: Player, frames: int) -> void:
	Input.action_press("move_forward")
	for i in range(frames):
		await get_tree().physics_frame
	Input.action_release("move_forward")


func test_the_player_walks_up_a_curb_a_foot_tall() -> void:
	_floor_and_step(0.3)
	var player: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(player)
	player.global_position = Vector3(0, 0.05, 0)
	await _walk_forward(player, 120)
	assert_float(player.global_position.y).is_equal_approx(0.3, 0.06)
	assert_float(player.global_position.z).is_less(-2.5)


func test_a_wall_is_not_a_step() -> void:
	_floor_and_step(0.8)
	var player: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(player)
	player.global_position = Vector3(0, 0.05, 0)
	await _walk_forward(player, 120)
	assert_float(player.global_position.y).is_less(0.1)
	assert_float(player.global_position.z).is_greater(-2.1)
