extends GdUnitTestSuite
## "Go to" from the map legend puts the player outside the place's building: a shop's place is
## its OSM point inside the building, and a player put down in a block's building was stuck.

const PlayTestbed := preload("res://scenes/play_testbed.gd")


## A building whose outer ring is the square from (x0, z0) to (x1, z1), with optional courtyard rings.
func _building(x0: float, z0: float, x1: float, z1: float, courts: Array = []) -> BuildingBuilder.Building:
	var b := BuildingBuilder.Building.new()
	b.rings.append(PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]))
	for c: PackedVector2Array in courts:
		b.rings.append(c)
	return b


func test_with_no_building_it_stands_a_few_metres_toward_the_street() -> void:
	var empty: Array[BuildingBuilder.Building] = []
	var at := PlayTestbed.go_to_point(Vector3(0, 5, 0), Vector3(40, 0, 0), empty)
	assert_vector(at).is_equal_approx(Vector3(4, 5, 0), Vector3.ONE * 0.01)


func test_a_place_inside_a_building_lands_a_metre_outside_it_toward_the_street() -> void:
	var buildings: Array[BuildingBuilder.Building] = [_building(-10, -10, 10, 10)]
	var at := PlayTestbed.go_to_point(Vector3(0, 5, 0), Vector3(40, 0, 0), buildings)
	assert_float(at.x).is_greater_equal(11.0)
	assert_float(at.x).is_less(13.0)
	assert_float(at.z).is_equal_approx(0.0, 0.01)
	assert_bool(PlayTestbed._in_a_building(Vector2(at.x, at.z), buildings, 1.0)).is_false()


func test_a_courtyard_counts_as_outside() -> void:
	var court := PackedVector2Array([Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)])
	var buildings: Array[BuildingBuilder.Building] = [_building(-10, -10, 10, 10, [court])]
	assert_bool(PlayTestbed._in_a_building(Vector2(0, 0), buildings, 0.0)).is_false()
	assert_bool(PlayTestbed._in_a_building(Vector2(6, 0), buildings, 0.0)).is_true()


func test_when_the_whole_way_is_built_over_it_goes_to_the_street() -> void:
	var buildings: Array[BuildingBuilder.Building] = [_building(-10, -10, 50, 10)]
	var at := PlayTestbed.go_to_point(Vector3(0, 5, 0), Vector3(40, 0, 0), buildings)
	assert_vector(at).is_equal_approx(Vector3(40, 5, 0), Vector3.ONE * 0.01)


func test_a_place_already_at_its_street_stays_put() -> void:
	var empty: Array[BuildingBuilder.Building] = []
	assert_vector(PlayTestbed.go_to_point(Vector3(3, 1, 3), Vector3(3.5, 0, 3), empty)).is_equal(Vector3(3, 1, 3))
