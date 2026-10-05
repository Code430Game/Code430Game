extends GdUnitTestSuite
## add-police 1.1: crimes count only when seen, stars cap, and they drop out of police sight.


func _manager_with_walker_at(pos: Vector3) -> PedestrianManager:
	var w := RoadGraph.PedestrianWay.new()
	w.id = "p1"
	w.kind = "sidewalk"
	w.width_m = 2.0
	w.road_class = "footway"
	w.polyline = PackedVector3Array([pos - Vector3(50, 0, 0), pos + Vector3(50, 0, 0)])
	var m: PedestrianManager = auto_free(PedestrianManager.new())
	add_child(m)
	m.setup(WalkGraph.build([w] as Array[RoadGraph.PedestrianWay]))
	m.enabled = false
	var a := Pedestrian.new()
	a.path_id = 0
	a.distance = 50.0
	a.transform = Transform3D(Basis(), pos)
	m.agents.append(a)
	return m


func _wanted() -> Wanted:
	var w: Wanted = auto_free(Wanted.new())
	add_child(w)
	return w


func test_an_unseen_crime_does_not_count_and_a_witnessed_one_does() -> void:
	var w := _wanted()
	w.peds = _manager_with_walker_at(Vector3(0, 0, 0))
	assert_bool(w.report("gunfire", Vector3(500, 0, 500))).is_false()
	assert_int(w.stars).is_equal(0)
	assert_bool(w.report("gunfire", Vector3(5, 0, 0))).is_true()
	assert_int(w.stars).is_equal(1)
	w.report("assault_down", Vector3(5, 0, 0))
	w.report("assault_down", Vector3(5, 0, 0))
	assert_int(w.stars).is_equal(3)  # capped
	assert_str(w.stars_text()).is_equal("★★★")


func test_stars_drop_out_of_police_sight_and_hold_in_it() -> void:
	var w := _wanted()
	var target: Node3D = auto_free(Node3D.new())
	add_child(target)
	w.target = target
	w.police_positions = PackedVector3Array([Vector3(10, 0, 0)])  # police right there
	w.report("theft", Vector3(0, 0, 0))
	assert_int(w.stars).is_equal(1)
	for i in range(30):
		await get_tree().process_frame
	assert_float(w.unseen_s).is_equal(0.0)  # seen: the clock stands still
	w.police_positions = PackedVector3Array()
	w.config["lose_s"] = [0.0, 0.3, 0.3, 0.3]
	await get_tree().create_timer(0.6).timeout
	assert_int(w.stars).is_equal(0)
