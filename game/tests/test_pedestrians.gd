extends GdUnitTestSuite
## Walk graph joins, walking and turning, stopping for a player, hits, spawning.


func _ways(specs: Array) -> Array[RoadGraph.PedestrianWay]:
	var out: Array[RoadGraph.PedestrianWay] = []
	for spec in specs:
		var w := RoadGraph.PedestrianWay.new()
		w.id = spec["id"]
		w.kind = spec.get("kind", "sidewalk")
		w.width_m = spec.get("w", 2.0)
		w.road_class = "footway"
		w.covered = spec.get("covered", false)
		var pl := PackedVector3Array()
		for p in spec["pl"]:
			pl.append(Vector3(p[0], p[1], p[2]))
		w.polyline = pl
		out.append(w)
	return out


func _manager(ways: Array[RoadGraph.PedestrianWay]) -> PedestrianManager:
	var m: PedestrianManager = auto_free(PedestrianManager.new())
	add_child(m)
	m.setup(WalkGraph.build(ways))
	m.enabled = false
	return m


func _add(m: PedestrianManager, path_id: int, distance: float, forward: bool = true, speed: float = 1.4) -> Pedestrian:
	var a := Pedestrian.new()
	a.path_id = path_id
	a.distance = distance
	a.forward = forward
	a.speed = speed
	var p := m.walk.paths[path_id]
	a.transform = Transform3D(Basis(), p.position_at(distance))
	m.agents.append(a)
	return a


func test_ways_join_where_their_ends_meet_and_covered_ways_are_skipped() -> void:
	var g := WalkGraph.build(_ways([
		{"id": "p1", "pl": [[0, 0, 0], [100, 0, 0]]},
		{"id": "p2", "pl": [[100, 0, 0.4], [100, 0, 80]]},  # within the join tolerance
		{"id": "p3", "pl": [[300, 0, 0], [400, 0, 0]]},
		{"id": "p4", "pl": [[0, 0, 5], [50, 0, 5]], "covered": true},
	]))
	assert_int(g.paths.size()).is_equal(3)
	assert_array(g.connections(g.paths[0], true)).contains_exactly([1])
	assert_array(g.connections(g.paths[0], false)).is_empty()
	assert_array(g.connections(g.paths[2], true)).is_empty()


func test_pedestrian_walks_round_the_corner_and_reverses_at_the_dead_end() -> void:
	var m := _manager(_ways([
		{"id": "p1", "pl": [[0, 0, 0], [100, 0, 0]]},
		{"id": "p2", "pl": [[100, 0, 0], [100, 0, 60]]},
	]))
	m.anchors = PackedVector3Array([Vector3.ZERO])
	var a := _add(m, 0, 95.0, true, 1.5)
	for i in range(240):  # 4 s: round the corner onto p2
		m.step(1.0 / 60.0)
	assert_int(a.path_id).is_equal(1)
	assert_bool(a.forward).is_true()
	assert_float(a.position().x).is_equal_approx(100.0, 1.2)
	for i in range(60 * 45):  # long enough to reach p2's dead end and come back
		m.step(1.0 / 60.0)
	assert_bool(a.forward).is_false()


func test_pedestrian_stops_for_a_player_right_ahead() -> void:
	var m := _manager(_ways([{"id": "p1", "pl": [[0, 0, 0], [100, 0, 0]]}]))
	m.anchors = PackedVector3Array([Vector3.ZERO])
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	player.global_position = Vector3(30.0, 0.0, 0.0)
	m.obstacles = [player]
	var a := _add(m, 0, 20.0, true, 1.5)
	a.lateral = 0.0
	for i in range(300):  # 5 s would carry it 7.5 m, past the player
		m.step(1.0 / 60.0)
	assert_float(a.position().x).is_less(30.0 - float(m.config["stop_for_player_m"]) + 0.3)
	assert_float(a.position().x).is_greater(26.0)


func test_without_a_ragdoll_the_capsule_tumbles_then_lies_still_then_goes_away() -> void:
	# The ragdoll path is in test_character_ragdoll.gd; this is the fallback with an empty pool.
	var m: PedestrianManager = auto_free(PedestrianManager.new())
	add_child(m)
	m.config["ragdoll_pool"] = 0
	m.setup(WalkGraph.build(_ways([{"id": "p1", "pl": [[0, 0, 0], [100, 0, 0]]}])))
	m.enabled = false
	m.anchors = PackedVector3Array([Vector3.ZERO])
	var a := _add(m, 0, 20.0)
	m._assign_bodies()
	var body: PedestrianBody = a.body
	m.knock_down(a, Vector3(0, 100, -600), a.position() + Vector3.UP * 0.5)
	assert_int(a.state).is_equal(Pedestrian.State.HIT)
	assert_bool(body.freeze).is_false()
	for i in range(int(float(m.config["hit_physics_s"]) * 60) + 5):
		m.step(1.0 / 60.0)
	assert_int(a.state).is_equal(Pedestrian.State.DOWN)
	assert_bool(body.freeze).is_true()
	assert_int(body.collision_mask).is_equal(0)
	for i in range(int(float(m.config["remove_after_s"]) * 60) + 5):
		m.step(1.0 / 60.0)
	assert_int(m.agents.size()).is_equal(0)
	assert_object(body.agent).is_null()


func test_walkers_are_out_of_reach_of_vehicles_but_not_of_people() -> void:
	var m := _manager(_ways([{"id": "p1", "pl": [[0, 0, 0], [100, 0, 0]]}]))
	var body: PedestrianBody = m._bodies[0]
	assert_int(body.collision_layer).is_equal(PedestrianBody.LAYER)
	assert_int(body.collision_mask).is_equal(0)  # a frozen body touching a car is a wall to it
	var car: VehicleBody3D = auto_free(TrafficManager.DRIVABLE_CAR_SCENE.instantiate())
	assert_int(car.collision_mask & PedestrianBody.LAYER).is_equal(0)
	var player: Node = auto_free(load("res://actors/player/player.tscn").instantiate())
	assert_int((player as CharacterBody3D).collision_mask & PedestrianBody.LAYER).is_not_equal(0)


func test_person_on_foot_is_blocked_and_nobody_falls() -> void:
	var m := _manager(_ways([{"id": "p1", "pl": [[0, 0, 0], [100, 0, 0]]}]))
	m.anchors = PackedVector3Array([Vector3(20, 0, 0)])
	var a := _add(m, 0, 20.0)
	a.speed = 0.0
	m.enabled = false
	m._assign_bodies()
	assert_object(a.body).is_not_null()
	var walker_mask: int = (auto_free(load("res://actors/player/player.tscn").instantiate()) as CharacterBody3D).collision_mask
	var person := CharacterBody3D.new()
	person.collision_mask = walker_mask
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.95
	person.add_child(shape)
	add_child(person)
	auto_free(person)
	person.global_position = Vector3(20, 0.05, 2.0)
	for i in range(90):  # walk straight at the pedestrian for 1.5 s at 2 m/s
		person.velocity = Vector3(0, 0, -2.0)
		person.move_and_slide()
		await get_tree().physics_frame
	assert_float(person.global_position.z).is_greater(0.4)  # stopped against them
	assert_int(a.state).is_equal(Pedestrian.State.WALKING)


func test_traffic_car_knocks_a_walker_down() -> void:
	var m := _manager(_ways([{"id": "p1", "pl": [[0, 0, 0], [100, 0, 0]]}]))
	m.anchors = PackedVector3Array([Vector3(20, 0, 0)])
	var a := _add(m, 0, 20.0)
	a.speed = 0.0
	m._assign_bodies()
	var car: TrafficCar = auto_free(load("res://world/traffic/traffic_car.tscn").instantiate())
	add_child(car)
	var agent := TrafficAgent.new()
	agent.speed = 10.0
	agent.transform = Transform3D(Basis(), Vector3(20, 0, 8))  # facing -Z, toward the walker
	car.agent = agent
	for i in range(60):
		agent.transform.origin.z -= 10.0 / 60.0
		car.global_transform = agent.transform
		await get_tree().physics_frame
		if a.state != Pedestrian.State.WALKING:
			break
	assert_int(a.state).is_equal(Pedestrian.State.HIT)
	await get_tree().physics_frame  # the impulse lands on the next physics step
	await get_tree().physics_frame
	assert_float(m.thrown_velocity(a).z).is_less(-3.0)  # thrown the way the car was going


func test_spawning_respects_cap_and_distances() -> void:
	var specs := []
	for i in range(6):
		specs.append({"id": "p%d" % i, "pl": [[-200, 0, i * 30], [200, 0, i * 30]]})
	var m := _manager(_ways(specs))
	m.enabled = true
	m.max_agents = 30
	m.anchors = PackedVector3Array([Vector3(0, 0, 75)])
	for i in range(120):
		m._physics_process(1.0 / 60.0)
	assert_int(m.active_count()).is_between(1, 30)
	for a in m.agents:
		var d := Vector2(a.position().x, a.position().z - 75.0).length()
		assert_float(d).is_greater_equal(float(m.config["min_spawn_distance_m"]) - 2.5)


func _cross_with_signals() -> Dictionary:
	# An east-west road through a signalised node at the origin, and a crossing path over it.
	var nodes := {}
	var edges := []
	for spec in [["w1.0", [[-150, 0, 0], [0, 0, 0]]], ["w2.0", [[0, 0, 0], [150, 0, 0]]], ["w3.0", [[0, 0, -150], [0, 0, 0]]], ["w4.0", [[0, 0, 0], [0, 0, 150]]]]:
		var pl: Array = spec[1]
		for p in [pl[0], pl[1]]:
			var id := "n_%d_%d" % [int(p[0]), int(p[2])]
			nodes[id] = {"id": id, "position": p, "ground_y": 0, "junction_type": "junction", "control": "signals" if id == "n_0_0" else "none"}
		edges.append({
			"id": spec[0], "from": "n_%d_%d" % [int(pl[0][0]), int(pl[0][2])], "to": "n_%d_%d" % [int(pl[1][0]), int(pl[1][2])],
			"polyline": pl, "class": "secondary", "lanes_forward": 1, "lanes_backward": 0, "oneway": true, "speed_kph": 50,
			"width_m": 7.0, "layer": 0, "bridge": false, "tunnel": false, "name": spec[0], "osm_way_id": 1, "defaulted_fields": [], "access": null, "length_m": 150.0,
		})
	var graph := RoadGraph.from_dict({"meta": {}, "nodes": nodes.values(), "edges": edges, "pedestrian_ways": []})
	var tm: TrafficManager = auto_free(TrafficManager.new())
	add_child(tm)
	tm.setup(LaneGraph.build(graph, JunctionBuilder.build_all(graph)), graph)
	tm.enabled = false
	# A sidewalk along the road's south side ending at a crossing over w1.0 just west of the node.
	var ways := _ways([
		{"id": "s1", "pl": [[-80, 0, 6], [-12, 0, 6]], "kind": "sidewalk"},
		{"id": "c1", "pl": [[-12, 0, 6], [-12, 0, -6]], "kind": "crossing", "w": 3.0},
		{"id": "s2", "pl": [[-12, 0, -6], [-80, 0, -6]], "kind": "sidewalk"},
	])
	var pm: PedestrianManager = auto_free(PedestrianManager.new())
	add_child(pm)
	pm.setup(WalkGraph.build(ways), graph, tm)
	pm.enabled = false
	pm.anchors = PackedVector3Array([Vector3.ZERO])
	return {"graph": graph, "traffic": tm, "peds": pm}


func test_crossing_links_to_its_road_and_signal() -> void:
	var s := _cross_with_signals()
	var pm: PedestrianManager = s["peds"]
	var crossing: WalkGraph.WalkPath = pm.walk.paths[1]
	assert_str(crossing.kind).is_equal("crossing")
	assert_str(crossing.crossed_edge).is_equal("w1.0")
	assert_str(crossing.signal_node).is_equal("n_0_0")


func test_pedestrian_waits_for_the_red_then_crosses() -> void:
	var s := _cross_with_signals()
	var pm: PedestrianManager = s["peds"]
	var tm: TrafficManager = s["traffic"]
	var sc := tm.signals
	sc.green_s = 10.0
	sc.amber_s = 2.0
	sc.all_red_s = 1.0
	# Hold the road at green for a while: the walker must wait at the kerb.
	var phase := sc.phase_of("n_0_0", "w1.0")
	sc.time = -float(sc._offset["n_0_0"]) + (0.0 if phase == 0 else 13.0)
	assert_int(sc.light("n_0_0", "w1.0")).is_equal(TrafficManager.Signals.Light.GREEN)
	var a := _add(pm, 0, 66.0, true, 1.5)  # 2 m from the kerb
	for i in range(240):  # 4 s with the light green
		pm.step(1.0 / 60.0)
	assert_int(a.path_id).is_equal(0)
	assert_bool(a.waiting_to_cross).is_true()
	# Now the road's red: the walker steps onto the crossing.
	sc.time += 13.0
	assert_int(sc.light("n_0_0", "w1.0")).is_equal(TrafficManager.Signals.Light.RED)
	for i in range(120):
		pm.step(1.0 / 60.0)
	assert_int(a.path_id).is_equal(1)


func test_cars_yield_to_a_person_on_the_crossing() -> void:
	var s := _cross_with_signals()
	var tm: TrafficManager = s["traffic"]
	var lane_id := -1
	for p in tm.lanes.paths:
		if p.edge_id == "w1.0":
			lane_id = p.id
	var a := TrafficAgent.new()
	a.path_id = lane_id
	a.distance = 60.0
	a.speed = 12.0
	a.transform = Transform3D(Basis(), tm.lanes.paths[lane_id].position_at(60.0))
	tm.agents.append(a)
	# A person stands in the lane on the crossing, 138 m along (12 m before the node).
	tm.obstacle_points = PackedVector3Array([tm.lanes.paths[lane_id].position_at(138.0)])
	tm.signals.time = 0.0
	for i in range(600):
		tm.step(1.0 / 60.0)
	assert_float(a.speed).is_less(0.5)
	assert_float(a.distance).is_less(138.0 - 0.5 - float(tm.config["car_length_m"]) * 0.5 + 0.5)


func test_walkers_keep_off_cycle_lanes() -> void:
	# A sidewalk ends where a sidewalk and a cycleway both continue straight on.
	var m := _manager(_ways([
		{"id": "s1", "pl": [[0, 0, 0], [100, 0, 0]], "kind": "sidewalk"},
		{"id": "s2", "pl": [[100, 0, 0], [200, 0, 0.5]], "kind": "sidewalk"},
		{"id": "c1", "pl": [[100, 0, 0], [200, 0, -0.5]], "kind": "cycleway"},
	]))
	m.anchors = PackedVector3Array([Vector3.ZERO])
	var onto_cycleway := 0
	for trial in range(60):
		var a := _add(m, 0, 99.5, true, 1.5)
		m.step(1.0 / 60.0)
		m.step(1.0 / 60.0)
		if m.walk.paths[a.path_id].kind == "cycleway":
			onto_cycleway += 1
		m.agents.clear()
	assert_int(onto_cycleway).is_less(4)
	# And nobody spawns on one: a lone cycleway yields no pedestrians.
	var lonely := _manager(_ways([{"id": "c2", "pl": [[-200, 0, 50], [200, 0, 50]], "kind": "cycleway"}]))
	lonely.enabled = true
	lonely.anchors = PackedVector3Array([Vector3(0, 0, 50)])
	for i in range(60):
		lonely._physics_process(1.0 / 60.0)
	assert_int(lonely.active_count()).is_equal(0)
