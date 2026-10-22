extends GdUnitTestSuite
## #140: holding reset on foot puts the player on the nearest street, not back at the start;
## the start only when no street is near.

const PlayTestbed := preload("res://scenes/play_testbed.gd")


## A street along x at y 0, and a deck over it at y 20 from x 0 to 100 (z 30).
func _graph() -> RoadGraph:
	var nodes := [
		{"id": "a", "position": [0.0, 0.0, 0.0], "ground_y": 0.0, "junction_type": "junction", "control": "none", "osm_node_ids": [1]},
		{"id": "b", "position": [100.0, 0.0, 0.0], "ground_y": 0.0, "junction_type": "junction", "control": "none", "osm_node_ids": [2]},
		{"id": "c", "position": [0.0, 20.0, 30.0], "ground_y": 0.0, "junction_type": "junction", "control": "none", "osm_node_ids": [3]},
		{"id": "d", "position": [100.0, 20.0, 30.0], "ground_y": 0.0, "junction_type": "junction", "control": "none", "osm_node_ids": [4]},
	]
	var edges := []
	for e: Array in [["s", "a", "b", 0.0, 0.0], ["deck", "c", "d", 20.0, 30.0]]:
		edges.append({"id": e[0], "from": e[1], "to": e[2], "class": "residential", "polyline": [[0.0, e[3], e[4]], [100.0, e[3], e[4]]], "length_m": 100.0, "lanes_forward": 1, "lanes_backward": 1, "oneway": false, "speed_kph": 40, "width_m": 7.0, "layer": 0, "bridge": false, "tunnel": false, "name": null, "osm_way_id": 1, "control_from": "none", "control_to": "none"})
	return RoadGraph.from_dict({"nodes": nodes, "edges": edges, "pedestrian_ways": [], "bus_stops": []})


func test_it_goes_to_the_nearest_street() -> void:
	var start := Vector3(-500, 0, -500)
	var at := PlayTestbed.foot_reset_point(_graph(), Vector3(40, 1, -12), start)
	assert_vector(at).is_equal_approx(Vector3(40, 0, 0), Vector3.ONE * 0.01)


func test_it_prefers_the_street_about_level_with_the_player() -> void:
	# Nearer the deck in plan, but on the ground: the ground street, not the deck overhead.
	var at := PlayTestbed.foot_reset_point(_graph(), Vector3(60, 1, 22), Vector3.ZERO)
	assert_float(at.y).is_equal_approx(0.0, 0.01)


func test_with_no_street_near_it_goes_to_the_start() -> void:
	var start := Vector3(-500, 0, -500)
	assert_vector(PlayTestbed.foot_reset_point(_graph(), Vector3(2000, 0, 2000), start)).is_equal(start)
	assert_vector(PlayTestbed.foot_reset_point(null, Vector3.ZERO, start)).is_equal(start)
