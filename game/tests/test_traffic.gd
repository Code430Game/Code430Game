extends GdUnitTestSuite
## Traffic following, junction yielding, and spawning on synthetic lane graphs.


func _graph(specs: Array) -> RoadGraph:
	var nodes := {}
	var edges := []
	for spec in specs:
		var pl: Array = spec["pl"]
		for p in [pl[0], pl[pl.size() - 1]]:
			var id := "n_%d_%d" % [int(p[0]), int(p[2])]
			nodes[id] = {"id": id, "position": p, "ground_y": 0, "junction_type": "junction"}
		edges.append({
			"id": spec["id"], "from": "n_%d_%d" % [int(pl[0][0]), int(pl[0][2])], "to": "n_%d_%d" % [int(pl[pl.size() - 1][0]), int(pl[pl.size() - 1][2])],
			"polyline": pl, "class": spec.get("class", "secondary"), "lanes_forward": spec.get("lf", 1), "lanes_backward": spec.get("lb", 0),
			"oneway": spec.get("lb", 0) == 0, "speed_kph": spec.get("kph", 50), "width_m": spec.get("w", 7.0), "layer": 0, "bridge": false, "tunnel": false,
			"name": spec["id"], "osm_way_id": 1, "defaulted_fields": [], "access": null, "length_m": 100.0,
		})
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes.values(), "edges": edges, "pedestrian_ways": []})


func _manager(graph: RoadGraph) -> TrafficManager:
	var m: TrafficManager = auto_free(TrafficManager.new())
	add_child(m)
	m.setup(LaneGraph.build(graph, JunctionBuilder.build_all(graph)))
	m.enabled = false  # tests place agents and call step() themselves
	return m


func _add_agent(m: TrafficManager, path_id: int, distance: float, speed: float) -> TrafficAgent:
	var a := TrafficAgent.new()
	a.path_id = path_id
	a.distance = distance
	a.speed = speed
	a.transform = Transform3D(Basis(), m.lanes.paths[path_id].position_at(distance))
	m.agents.append(a)
	return a


func test_follower_never_overlaps_leader() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 60}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var leader := _add_agent(m, 0, 60.0, 4.0)
	var follower := _add_agent(m, 0, 20.0, 15.0)
	var min_seen := INF
	for i in range(600):
		leader.speed = 4.0  # leader holds 4 m/s regardless of its own control
		m.step(1.0 / 60.0)
		leader.speed = 4.0
		min_seen = minf(min_seen, leader.distance - follower.distance)
	assert_float(min_seen).is_greater(float(m.config["car_length_m"]))
	assert_float(follower.speed).is_less(6.0)  # settled behind the slow leader


func test_free_agent_reaches_speed_fraction_of_limit() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 50}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var a := _add_agent(m, 0, 10.0, 0.0)
	for i in range(300):
		m.step(1.0 / 60.0)
	assert_float(a.speed).is_equal_approx(50.0 / 3.6 * float(m.config["speed_fraction"]), 0.2)


func test_second_car_waits_for_occupied_junction() -> void:
	# Two one-way streets crossing at the origin; both cars arrive together.
	var g := _graph([
		{"id": "w1.0", "pl": [[-100, 0, 0], [0, 0, 0]]}, {"id": "w2.0", "pl": [[0, 0, 0], [100, 0, 0]]},
		{"id": "w3.0", "pl": [[0, 0, -100], [0, 0, 0]]}, {"id": "w4.0", "pl": [[0, 0, 0], [0, 0, 100]]},
	])
	var m := _manager(g)
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var east_id := -1
	var south_id := -1
	for p in m.lanes.paths:
		if p.edge_id == "w1.0":
			east_id = p.id
		if p.edge_id == "w3.0":
			south_id = p.id
	var east := _add_agent(m, east_id, 60.0, 10.0)
	var south := _add_agent(m, south_id, 58.0, 10.0)
	var both_inside := 0
	var waited := false
	for i in range(900):
		m.step(1.0 / 60.0)
		if east.occupies_junction != "" and south.occupies_junction != "":
			both_inside += 1
		if east.speed < 0.5 or south.speed < 0.5:
			waited = true
	assert_int(both_inside).is_equal(0)
	assert_bool(waited).is_true()
	# Both eventually cleared the junction.
	assert_str(m.lanes.paths[east.path_id].edge_id).is_not_equal("w1.0")
	assert_str(m.lanes.paths[south.path_id].edge_id).is_not_equal("w3.0")


func test_spawning_respects_cap_and_distances() -> void:
	var specs := []
	for i in range(6):
		specs.append({"id": "w%d.0" % i, "pl": [[-300, 0, i * 40], [300, 0, i * 40]], "lb": 1})
	var m := _manager(_graph(specs))
	m.enabled = true
	m.max_agents = 20
	m.anchors = PackedVector3Array([Vector3(0, 0, 100)])
	for i in range(80):
		m._physics_process(1.0 / 60.0)
	assert_int(m.active_count()).is_between(1, 20)
	for a in m.agents:
		var d := Vector2(a.position().x, a.position().z - 100.0).length()
		assert_float(d).is_greater_equal(float(m.config["min_spawn_distance_m"]) - 0.01)
		assert_float(d).is_less_equal(float(m.config["spawn_radius_m"]) + 300.0)


func test_agent_stops_behind_a_person_in_its_lane() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 60}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var person: Node3D = auto_free(Node3D.new())
	add_child(person)
	person.global_position = m.lanes.paths[0].position_at(80.0)
	m.obstacles = [person]
	var a := _add_agent(m, 0, 10.0, 15.0)
	for i in range(900):
		m.step(1.0 / 60.0)
	assert_float(a.speed).is_less(0.3)
	var stop_before := 80.0 - float(m.config["person_radius_m"]) - float(m.config["car_length_m"]) * 0.5
	assert_float(a.distance).is_less(stop_before)
	assert_float(a.distance).is_greater(stop_before - float(m.config["min_gap_m"]) - 3.0)


func test_agent_ignores_a_person_beside_the_lane() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 60}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var person: Node3D = auto_free(Node3D.new())
	add_child(person)
	person.global_position = m.lanes.paths[0].position_at(80.0) + Vector3(0, 0, 4.0)  # on the sidewalk
	m.obstacles = [person]
	var a := _add_agent(m, 0, 10.0, 15.0)
	for i in range(600):
		m.step(1.0 / 60.0)
	assert_float(a.distance).is_greater(150.0)


func test_followers_queue_behind_a_resting_hit_car() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 60}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var wreck := _add_agent(m, 0, 100.0, 0.0)
	wreck.retired = true
	wreck.resting = true
	var follower := _add_agent(m, 0, 20.0, 15.0)
	for i in range(900):
		m.step(1.0 / 60.0)
	assert_float(follower.speed).is_less(0.3)
	assert_float(follower.distance).is_less(100.0 - float(m.config["car_length_m"]))
	assert_float(follower.distance).is_greater(80.0)


func test_hit_car_facing_its_lane_resumes_driving() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 60}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var a := _add_agent(m, 0, 100.0, 0.0)
	# Knocked 1.5 m sideways but still facing along the lane; no physics body in the test.
	var lane_dir := m.lanes.paths[0].direction_at(100.0)
	a.transform = Transform3D(Basis.looking_at(lane_dir, Vector3.UP), m.lanes.paths[0].position_at(100.0) + Vector3(0, 0, 1.5))
	a.retired = true
	a.hit_timer = 0.5
	for i in range(300):
		m.step(1.0 / 60.0)
	assert_bool(a.retired).is_false()
	assert_float(a.speed).is_greater(1.0)
	assert_float(a.distance).is_greater(100.0)


func test_hit_car_facing_across_the_lane_rests_and_blocks() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 60}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var a := _add_agent(m, 0, 100.0, 0.0)
	var lane_dir := m.lanes.paths[0].direction_at(100.0)
	var across := lane_dir.cross(Vector3.UP)
	a.transform = Transform3D(Basis.looking_at(across, Vector3.UP), m.lanes.paths[0].position_at(100.0))
	a.retired = true
	a.hit_timer = 0.2
	for i in range(60):
		m.step(1.0 / 60.0)
	assert_bool(a.retired).is_true()
	assert_bool(a.resting).is_true()
	assert_float(a.distance).is_equal_approx(100.0, 0.5)


func test_take_car_spawns_a_drivable_car_in_the_agent_colour() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 60}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var a := _add_agent(m, 0, 50.0, 0.0)
	a.color = Color(0.2, 0.45, 0.25)
	var body: TrafficCar = m._bodies[0]
	a.body = body
	body.agent = a
	var car := m.take_car(body)
	assert_object(car).is_not_null()
	assert_bool(car.is_in_group("vehicles")).is_true()
	assert_int(m.agents.size()).is_equal(0)
	assert_object(body.agent).is_null()
	assert_float(car.global_position.distance_to(m.lanes.paths[0].position_at(50.0))).is_less(1.0)
	var mesh := car.get_node("Mesh") as MeshInstance3D
	assert_object((mesh.material_override as StandardMaterial3D).albedo_color).is_equal(Color(0.2, 0.45, 0.25))
	car.queue_free()
