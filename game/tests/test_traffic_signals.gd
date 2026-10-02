extends GdUnitTestSuite
## Signal phases and traffic obeying lights and stop signs on a synthetic cross.

const Signals := preload("res://world/traffic/signal_controller.gd")


func _cross(control: String) -> RoadGraph:
	# Four one-way streets into and out of the origin: east-west and north-south pairs.
	var nodes := {}
	var edges := []
	var specs := [
		["w1.0", [[-150, 0, 0], [0, 0, 0]]], ["w2.0", [[0, 0, 0], [150, 0, 0]]],
		["w3.0", [[0, 0, -150], [0, 0, 0]]], ["w4.0", [[0, 0, 0], [0, 0, 150]]],
	]
	for spec in specs:
		var pl: Array = spec[1]
		for p in [pl[0], pl[1]]:
			var id := "n_%d_%d" % [int(p[0]), int(p[2])]
			nodes[id] = {"id": id, "position": p, "ground_y": 0, "junction_type": "junction", "control": control if id == "n_0_0" else "none"}
		edges.append({
			"id": spec[0], "from": "n_%d_%d" % [int(pl[0][0]), int(pl[0][2])], "to": "n_%d_%d" % [int(pl[1][0]), int(pl[1][2])],
			"polyline": pl, "class": "secondary", "lanes_forward": 1, "lanes_backward": 0, "oneway": true, "speed_kph": 50,
			"width_m": 7.0, "layer": 0, "bridge": false, "tunnel": false, "name": spec[0], "osm_way_id": 1, "defaulted_fields": [], "access": null, "length_m": 150.0,
		})
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes.values(), "edges": edges, "pedestrian_ways": []})


func _manager(graph: RoadGraph) -> TrafficManager:
	var m: TrafficManager = auto_free(TrafficManager.new())
	add_child(m)
	m.setup(LaneGraph.build(graph, JunctionBuilder.build_all(graph)), graph)
	m.enabled = false
	m.anchors = PackedVector3Array([Vector3.ZERO])
	return m


func _agent_on(m: TrafficManager, edge_id: String, distance: float, speed: float) -> TrafficAgent:
	for p in m.lanes.paths:
		if p.edge_id == edge_id:
			var a := TrafficAgent.new()
			a.path_id = p.id
			a.distance = distance
			a.speed = speed
			a.transform = Transform3D(Basis(), p.position_at(distance))
			m.agents.append(a)
			return a
	return null


func test_two_phases_alternate_and_never_share_green() -> void:
	var graph := _cross("signals")
	var sc := Signals.new()
	sc.setup(graph, {"signal_green_s": 10.0, "signal_amber_s": 2.0, "signal_all_red_s": 1.0})
	assert_bool(sc.is_signalised("n_0_0")).is_true()
	assert_int(sc.phase_of("n_0_0", "w1.0")).is_equal(sc.phase_of("n_0_0", "w2.0"))
	assert_int(sc.phase_of("n_0_0", "w1.0")).is_not_equal(sc.phase_of("n_0_0", "w3.0"))
	var greens_a := 0
	var greens_b := 0
	for i in range(260):  # one full 26 s cycle in 0.1 s steps
		var la := sc.light("n_0_0", "w1.0")
		var lb := sc.light("n_0_0", "w3.0")
		assert_bool(la == Signals.Light.GREEN and lb == Signals.Light.GREEN).is_false()
		if la == Signals.Light.GREEN:
			greens_a += 1
		if lb == Signals.Light.GREEN:
			greens_b += 1
		sc.advance(0.1)
	assert_int(greens_a).is_between(95, 105)
	assert_int(greens_b).is_between(95, 105)


func test_car_waits_at_red_and_goes_on_green() -> void:
	var m := _manager(_cross("signals"))
	var sc := m.signals
	sc.green_s = 10.0
	sc.amber_s = 2.0
	sc.all_red_s = 1.0
	var phase := sc.phase_of("n_0_0", "w1.0")
	# Wind the clock to the start of the other phase's green so our approach is red.
	sc.time = -float(sc._offset["n_0_0"]) + (0.0 if phase == 1 else 13.0)
	assert_int(sc.light("n_0_0", "w1.0")).is_equal(Signals.Light.RED)
	var a := _agent_on(m, "w1.0", 100.0, 12.0)
	var lane_len: float = m.lanes.paths[a.path_id].length
	for i in range(300):  # 5 s: must be stopped at the line, still red
		m.signals.advance(1.0 / 60.0)
		m.step(1.0 / 60.0)
	assert_float(a.speed).is_less(0.3)
	assert_str(m.lanes.paths[a.path_id].edge_id).is_equal("w1.0")
	assert_float(a.distance).is_less_equal(lane_len - 0.4)
	for i in range(900):  # 15 s more: green comes and it crosses
		m.signals.advance(1.0 / 60.0)
		m.step(1.0 / 60.0)
	assert_str(m.lanes.paths[a.path_id].edge_id).is_not_equal("w1.0")


func test_car_comes_to_a_full_stop_at_a_stop_sign_then_proceeds() -> void:
	var m := _manager(_cross("stop"))
	var a := _agent_on(m, "w1.0", 100.0, 12.0)
	var stopped := false
	var crossed := false
	for i in range(1200):
		m.step(1.0 / 60.0)
		if a.speed < 0.2 and m.lanes.paths[a.path_id].edge_id == "w1.0":
			stopped = true
		if m.lanes.paths[a.path_id].edge_id != "w1.0" and not m.lanes.paths[a.path_id].is_connector:
			crossed = true
			break
	assert_bool(stopped).is_true()
	assert_bool(crossed).is_true()


func test_stop_on_the_side_street_only_stops_the_side_street() -> void:
	var graph := _cross("none")
	# The north-south pair carries stops on the approaches; east-west is free.
	graph.edges["w3.0"].control_to = "stop"
	assert_str(graph.approach_control(graph.edges["w3.0"], "n_0_0")).is_equal("stop")
	assert_str(graph.approach_control(graph.edges["w1.0"], "n_0_0")).is_equal("none")
	var m := _manager(graph)
	var east := _agent_on(m, "w1.0", 100.0, 12.0)
	var south := _agent_on(m, "w3.0", 100.0, 12.0)
	var east_stopped := false
	var south_stopped := false
	for i in range(900):
		m.step(1.0 / 60.0)
		if east.speed < 0.2 and m.lanes.paths[east.path_id].edge_id == "w1.0":
			east_stopped = true
		if south.speed < 0.2 and m.lanes.paths[south.path_id].edge_id == "w3.0":
			south_stopped = true
	assert_bool(south_stopped).is_true()
	assert_bool(east_stopped).is_false()


func test_a_signal_on_an_approach_makes_the_junction_signalised() -> void:
	var graph := _cross("none")
	graph.edges["w1.0"].control_to = "signals"
	assert_bool(graph.is_signalised("n_0_0")).is_true()
	assert_str(graph.approach_control(graph.edges["w3.0"], "n_0_0")).is_equal("signals")
	var m := _manager(graph)
	assert_bool(m.signals.is_signalised("n_0_0")).is_true()
	var heads := SignalHeads.new()
	add_child(heads)
	heads.setup(graph, JunctionBuilder.build_all(graph), m.signals)
	assert_int(heads.count()).is_equal(2)  # the two arriving approaches
	assert_int(heads.sign_count()).is_equal(0)
	heads.queue_free()


func test_head_lamps_glow_in_their_own_colour_at_night() -> void:
	# The lamp material emits the instance colour scaled by the night factor, never a flat tint.
	var m := SignalHeads.head_material()
	assert_object(m).is_instanceof(ShaderMaterial)
	assert_float(float(m.get_shader_parameter("night_energy"))).is_equal_approx(SignalHeads.HEAD_NIGHT_ENERGY, 1e-6)
	var src: String = (m.shader as Shader).code
	assert_bool(src.contains("EMISSION = COLOR.rgb")).is_true()
