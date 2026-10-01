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


func test_hit_pedestrian_tumbles_then_lies_still_then_goes_away() -> void:
	var m := _manager(_ways([{"id": "p1", "pl": [[0, 0, 0], [100, 0, 0]]}]))
	m.anchors = PackedVector3Array([Vector3.ZERO])
	var a := _add(m, 0, 20.0)
	var body: PedestrianBody = m._bodies[0]
	a.body = body
	body.agent = a
	m._on_body_hit(body)
	assert_int(a.state).is_equal(Pedestrian.State.HIT)
	assert_bool(body.freeze).is_false()
	for i in range(int(float(m.config["hit_physics_s"]) * 60) + 5):
		m.step(1.0 / 60.0)
	assert_int(a.state).is_equal(Pedestrian.State.DOWN)
	assert_bool(body.freeze).is_true()
	for i in range(int(float(m.config["remove_after_s"]) * 60) + 5):
		m.step(1.0 / 60.0)
	assert_int(m.agents.size()).is_equal(0)
	assert_object(body.agent).is_null()


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
