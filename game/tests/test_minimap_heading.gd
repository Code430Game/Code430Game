extends GdUnitTestSuite
## The minimap and the overview map's arrow turn with the camera's look on foot and with the
## car's heading when driving (human, 2026-10-08: "the arrow should be following where you
## are facing; it seemed to be off").


func _body_facing(dir: Vector3) -> Node3D:
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	n.look_at_from_position(Vector3.ZERO, dir, Vector3.UP)  # -Z of the basis points along dir
	return n


func test_on_foot_the_map_turns_with_the_camera_not_the_body() -> void:
	var minimap: Minimap = auto_free(Minimap.new())
	add_child(minimap)
	minimap.player = _body_facing(Vector3.RIGHT)  # the body walks east
	minimap.heading_source = func() -> Vector3: return Vector3.FORWARD  # the camera looks north
	assert_vector(minimap.heading()).is_equal_approx(Vector3.FORWARD, Vector3(0.001, 0.001, 0.001))
	assert_float(Minimap.map_rotation_for(minimap.heading())).is_equal_approx(0.0, 1e-5)


func test_in_a_car_the_map_turns_with_the_car() -> void:
	var minimap: Minimap = auto_free(Minimap.new())
	add_child(minimap)
	minimap.player = _body_facing(Vector3.RIGHT)  # the car points east
	minimap.heading_source = Callable()
	assert_vector(minimap.heading()).is_equal_approx(Vector3.RIGHT, Vector3(0.001, 0.001, 0.001))
	assert_float(Minimap.map_rotation_for(minimap.heading())).is_equal_approx(-PI * 0.5, 1e-5)


func test_a_tilted_look_is_flattened_and_an_empty_one_falls_back_to_the_body() -> void:
	var minimap: Minimap = auto_free(Minimap.new())
	add_child(minimap)
	minimap.player = _body_facing(Vector3.BACK)
	minimap.heading_source = func() -> Vector3: return Vector3(0.0, -0.9, -0.1)  # looking down and north
	assert_vector(minimap.heading()).is_equal_approx(Vector3.FORWARD, Vector3(0.001, 0.001, 0.001))
	minimap.heading_source = func() -> Vector3: return Vector3.UP  # straight down: no horizontal part
	assert_vector(minimap.heading()).is_equal_approx(Vector3.BACK, Vector3(0.001, 0.001, 0.001))


func test_the_overview_arrow_uses_the_same_source() -> void:
	var overview: OverviewMap = auto_free(load("res://ui/map/overview_map.tscn").instantiate())
	add_child(overview)
	overview.player = _body_facing(Vector3.RIGHT)
	assert_vector(overview.heading_vector()).is_equal_approx(Vector3.RIGHT, Vector3(0.001, 0.001, 0.001))
	overview.heading_source = func() -> Vector3: return Vector3.FORWARD
	assert_vector(overview.heading_vector()).is_equal_approx(Vector3.FORWARD, Vector3(0.001, 0.001, 0.001))
	assert_object(overview.strip).is_not_null()
