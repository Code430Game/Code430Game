extends GdUnitTestSuite
## Minimap markers beyond the map's edge are pinned to the edge in their direction, so a
## chasing police car or the helicopter stays visible (human, 2026-10-06).


func test_a_marker_inside_the_map_stays_put() -> void:
	var inner := Rect2(Vector2(6, 6), Vector2(188, 188))
	assert_vector(Minimap.pin_to_edge(Vector2(150, 40), Vector2(100, 100), inner)).is_equal(Vector2(150, 40))


func test_a_marker_beyond_the_edge_sits_on_the_edge_in_its_direction() -> void:
	var inner := Rect2(Vector2(6, 6), Vector2(188, 188))
	var centre := Vector2(100, 100)
	var east := Minimap.pin_to_edge(Vector2(500, 100), centre, inner)
	assert_vector(east).is_equal_approx(Vector2(194, 100), Vector2(0.01, 0.01))
	var corner := Minimap.pin_to_edge(Vector2(-300, -300), centre, inner)
	assert_vector(corner).is_equal_approx(Vector2(6, 6), Vector2(0.01, 0.01))
	var steep := Minimap.pin_to_edge(Vector2(150, 1000), centre, inner)
	assert_float(steep.y).is_equal_approx(194.0, 0.01)
	assert_float(steep.x).is_between(100.0, 106.0)
