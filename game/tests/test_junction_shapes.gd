extends GdUnitTestSuite
## Junction outlines that follow their roads (update-junction-surfaces): no bulge into the grass
## and no notch back across a road (#78 "junction turns into ball", #79 the "C" at a T), checked
## with JunctionReport's measures on small fixtures.


## A graph with one junction "centre" at the origin and an arm per entry:
## [id, end point (x, z), width, origin offset (x, z)]. The arm runs straight from the
## origin offset to the end point.
func _graph(arms: Array) -> RoadGraph:
	var nodes := [{"id": "centre", "position": [0, 0, 0], "ground_y": 0, "junction_type": "junction"}]
	var edges := []
	for arm: Array in arms:
		var end: Vector2 = arm[1]
		var off: Vector2 = arm[3] if arm.size() > 3 else Vector2.ZERO
		nodes.append({"id": "end_" + arm[0], "position": [end.x, 0, end.y], "ground_y": 0, "junction_type": "dead_end"})
		edges.append({
			"id": "w%s.0" % arm[0], "from": "centre", "to": "end_" + arm[0], "polyline": [[off.x, 0, off.y], [end.x, 0, end.y]],
			"class": "residential", "lanes_forward": 1, "lanes_backward": 1, "oneway": false, "speed_kph": 40,
			"width_m": float(arm[2]), "layer": 0, "bridge": false, "tunnel": false, "name": arm[0], "osm_way_id": 1,
			"defaulted_fields": [], "access": null, "length_m": 100.0,
		})
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})


## A point `deg` degrees round from +x, `r` metres out.
func _at(deg: float, r: float = 100.0) -> Vector2:
	return Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * r


func _check(graph: RoadGraph, max_bulge: float = 0.3, max_gap: float = 0.1) -> JunctionBuilder.Junction:
	var j := JunctionBuilder.build_one(graph, "centre")
	assert_bool(j.fallback_hull).override_failure_message("the outline crossed itself: %s" % [j.polygon_xz]).is_false()
	var bulge := JunctionReport.bulge_m(graph, j)
	var gap := JunctionReport.gap_m(graph, j)
	assert_float(bulge).override_failure_message("bulges %.2f m into the grass: %s" % [bulge, j.polygon_xz]).is_less_equal(max_bulge)
	assert_float(gap).override_failure_message("leaves %.2f m of an arm uncovered: %s" % [gap, j.polygon_xz]).is_less_equal(max_gap)
	return j


func test_a_road_running_straight_through_a_t_keeps_its_far_edge() -> void:
	# #79: Graham Avenue straight through, a parking aisle off one side. The two through arms are
	# a hair off straight either way, which sent the old corner into the grass or back across.
	for bend: float in [-0.9, 0.0, 0.9]:
		var j := _check(_graph([["e", _at(0.0), 3.5], ["w", _at(180.0 + bend), 3.5], ["s", _at(90.0), 5.5]]))
		for p in j.polygon_xz:
			# The far side, away from the aisle, stays on the road's edge (y -1.75), give or take
			# the slight bend over the trim.
			assert_float(p.y).override_failure_message("vertex %s is past the far edge (bend %.1f)" % [p, bend]).is_greater_equal(-1.75 - 0.2)


func test_a_two_way_road_meeting_its_carriageways_head_on_has_no_ball() -> void:
	# #78: Colonel By Drive. A two-way road meets the two one-way carriageways it splits into,
	# both drawn from the same node a few degrees apart.
	_check(_graph([["two", _at(60.7), 7.0], ["a", _at(-118.9), 3.5], ["b", _at(-110.3), 3.5]]), 0.3, 0.5)


func test_the_outside_of_a_bend_turns_sharp_and_leaves_no_gap() -> void:
	_check(_graph([["e", _at(10.0), 7.0], ["w", _at(170.0), 7.0], ["s", _at(-90.0), 5.0]]))


func test_a_narrow_road_meeting_a_wide_one_at_an_obtuse_angle_takes_the_edge_crossing() -> void:
	# The narrow road's edge crosses the wide road's just behind the node: that is the corner,
	# not one pushed metres into the grass between them.
	_check(_graph([["a", _at(-120.0), 14.0], ["b", _at(60.0), 14.0], ["c", _at(175.0), 3.5]]))


func test_divided_carriageways_whose_ribbons_touch_are_both_covered() -> void:
	# A clustered junction: a divided road's two carriageways leave the same way with their
	# ribbons overlapping by under a metre; the outline must cover both ends.
	var n := Vector2(-sin(deg_to_rad(-32.0)), cos(deg_to_rad(-32.0)))
	_check(_graph([
		["d1", _at(-32.0) + n * 4.85, 10.5, n * 4.85],
		["d2", _at(-32.0) - n * 4.85, 10.5, -n * 4.85],
		["x", _at(58.0), 7.0],
		["y", _at(148.0), 10.5],
	]), 0.3, 0.1)
