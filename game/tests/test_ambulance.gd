extends GdUnitTestSuite
## add-ambulance-response 1.x: calls, dispatch from a base, tending by tone, holding the body.

var _mode_before: String


func before_test() -> void:
	_mode_before = ContentMode.current


func after_test() -> void:
	ContentMode.set_mode(_mode_before, false)


## A straight road east from the origin, a node every 20 m to 400 m.
func _graph() -> RoadGraph:
	var nodes := {}
	var edges := []
	for i in range(21):
		nodes["n%d" % i] = {"id": "n%d" % i, "position": [i * 20.0, 0.0, 0.0], "ground_y": 0.0, "junction_type": "junction", "control": "none", "osm_node_ids": [i]}
	for i in range(20):
		edges.append({"id": "w%d" % i, "from": "n%d" % i, "to": "n%d" % (i + 1), "class": "residential", "polyline": [[i * 20.0, 0.0, 0.0], [(i + 1) * 20.0, 0.0, 0.0]], "length_m": 20.0, "lanes_forward": 1, "lanes_backward": 1, "oneway": false, "speed_kph": 40, "width_m": 7.0, "layer": 0, "bridge": false, "tunnel": false, "name": null, "osm_way_id": i, "control_from": "none", "control_to": "none"})
	return RoadGraph.from_dict({"nodes": nodes.values(), "edges": edges, "pedestrian_ways": [], "bus_stops": []})


## The world: a floor, pedestrians (no walk graph, so nobody spawns), and the ambulances with
## one hospital whose road node is `base_node`.
func _setup(base_node: String) -> AmbulanceManager:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(800, 1, 800)
	shape.shape = box
	floor.add_child(shape)
	holder.add_child(floor)
	floor.position = Vector3(200, -0.5, 0)
	var peds: PedestrianManager = auto_free(PedestrianManager.new())
	add_child(peds)
	var am: AmbulanceManager = auto_free(AmbulanceManager.new())
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(AmbulanceManager.CONFIG_PATH))
	am.config = data
	am.config["call_delay_s"] = 0.1
	am.config["tend_s"] = 0.3
	am.config["medic_speed_mps"] = 12.0
	am.peds = peds
	am.graph = _graph()
	am.holder = holder
	var base := Services.Place.new()
	base.kind = "hospital"
	base.road_node = base_node
	base.at = am.graph.nodes[base_node].position + Vector3(0, 0, 15)
	am.bases = [base]
	add_child(am)
	return am


func _downed(am: AmbulanceManager, at: Vector3) -> Pedestrian:
	var a := Pedestrian.new()
	a.state = Pedestrian.State.DOWN
	a.timer = 25.0
	a.transform = Transform3D(Basis(), at)
	am.peds.agents.append(a)
	am.peds.downed.emit(a)
	return a


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func test_a_downed_person_opens_a_call_and_is_held() -> void:
	var am := _setup("n1")
	var a := _downed(am, Vector3(40, 0, 3))
	assert_int(am.calls.size()).is_equal(1)
	assert_bool(a.held).is_true()
	# Held: the removal timer running out does not clear them.
	a.timer = 0.0
	am.config["call_delay_s"] = 99.0
	am.peds.step(0.1)
	assert_bool(am.peds.agents.has(a)).is_true()


func test_calls_nearby_merge_and_only_max_out_ambulances_go() -> void:
	var am := _setup("n10")
	am.config["max_out"] = 1
	_downed(am, Vector3(100, 0, 3))
	_downed(am, Vector3(105, 0, 4))  # within merge_m of the first
	_downed(am, Vector3(300, 0, 3))
	assert_int(am.calls.size()).is_equal(2)
	assert_int(am.calls[0].people.size()).is_equal(2)
	await _frames(15)
	assert_int(am.runs.size()).is_equal(1)


func test_the_ambulance_drives_from_the_hospital_to_the_person() -> void:
	var am := _setup("n12")
	am.config["cruise_kph"] = 90.0
	_downed(am, Vector3(60, 0, 3))
	await _frames(15)
	assert_int(am.runs.size()).is_equal(1)
	var r: AmbulanceManager.Run = am.runs[0]
	assert_float(r.car.global_position.x).is_greater(200.0)  # pulled out of the hospital road
	var arrived := false
	for i in range(900):
		await get_tree().physics_frame
		if r.phase != AmbulanceManager.Phase.DRIVE:
			arrived = true
			break
	assert_bool(arrived).is_true()
	assert_float(Vector2(r.car.global_position.x - 60.0, r.car.global_position.z - 3.0).length()).is_less(12.0)


func test_clean_tone_stands_them_up_and_the_ambulance_leaves() -> void:
	ContentMode.set_mode("clean", false)
	var am := _setup("n1")  # pulls out right beside them
	var a := _downed(am, Vector3(40, 0, 3))
	var done := false
	for i in range(300):
		await get_tree().physics_frame
		if not am.runs.is_empty() and am.runs[0].phase == AmbulanceManager.Phase.RETURN:
			done = true
			break
	assert_bool(done).is_true()
	assert_int(a.state).is_equal(Pedestrian.State.WALKING)
	assert_bool(am.peds.agents.has(a)).is_true()
	assert_bool(a.held).is_false()
	assert_int(am.calls.size()).is_equal(0)


func test_gritty_tone_carries_them_off() -> void:
	ContentMode.set_mode("gritty", false)
	var am := _setup("n1")
	var a := _downed(am, Vector3(40, 0, 3))
	for i in range(300):
		await get_tree().physics_frame
		if not am.peds.agents.has(a):
			break
	assert_bool(am.peds.agents.has(a)).is_false()


func test_a_call_with_nobody_left_closes() -> void:
	var am := _setup("n10")
	am.config["call_delay_s"] = 99.0
	var a := _downed(am, Vector3(100, 0, 3))
	am.peds.carry_off(a)  # cleared by something else
	await _frames(2)
	assert_int(am.calls.size()).is_equal(0)


func test_walkers_wait_at_a_crossing_for_an_ambulance_coming_at_it() -> void:
	var am := _setup("n10")
	var path := WalkGraph.WalkPath.new()
	path.kind = "crossing"
	path.crossed_edge = "w5"
	path.points = PackedVector3Array([Vector3(100, 0, -4), Vector3(100, 0, 4)])
	path.cumulative = PackedFloat32Array([0.0, 8.0])
	path.length = 8.0
	assert_bool(am.peds.crossing_open(path)).is_true()
	var van: Node3D = auto_free(Node3D.new())
	add_child(van)
	van.global_position = Vector3(130, 0, 0)
	van.look_at(Vector3(100, 0, 0), Vector3.UP)  # heading for the crossing
	am.peds.emergency = [van]
	assert_bool(am.peds.crossing_open(path)).is_false()
	van.look_at(Vector3(200, 0, 0), Vector3.UP)  # driving away
	assert_bool(am.peds.crossing_open(path)).is_true()
