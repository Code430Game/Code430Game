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
			"oneway": spec.get("lb", 0) == 0, "speed_kph": spec.get("kph", 50), "width_m": spec.get("w", 7.0), "layer": 0, "bridge": false, "tunnel": spec.get("tunnel", false),
			"name": spec["id"], "osm_way_id": 1, "defaulted_fields": [], "access": null, "length_m": 100.0,
			"bus": spec.get("bus", ""), "bus_lane": spec.get("bus_lane", -1),
		})
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes.values(), "edges": edges, "pedestrian_ways": [], "bus_stops": []})


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


func test_snow_scales_the_lane_limit_by_the_weather_factor() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 50}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var table: Dictionary = m.config["weather_speed_factor"]
	m.weather_speed_factor = float(table["snow"])
	var a := _add_agent(m, 0, 10.0, 0.0)
	for i in range(300):
		m.step(1.0 / 60.0)
	assert_float(a.speed).is_equal_approx(50.0 / 3.6 * float(m.config["speed_fraction"]) * 0.7, 0.2)


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
	var seed_before := TrafficManager.station_seed(a)
	var car := m.take_car(body)
	assert_object(car).is_not_null()
	assert_bool(car.is_in_group("vehicles")).is_true()
	assert_str(str(car.get("radio_station"))).is_equal(Radio.pick_for_car(seed_before))
	assert_int(m.agents.size()).is_equal(0)
	assert_object(body.agent).is_null()
	assert_float(car.global_position.distance_to(m.lanes.paths[0].position_at(50.0))).is_less(1.0)
	var mesh := car.get_node("Mesh") as MeshInstance3D
	assert_object(car.get("body_color")).is_equal(Color(0.2, 0.45, 0.25))
	assert_object((mesh.get_surface_override_material(0) as StandardMaterial3D).albedo_color).is_equal(Color(0.2, 0.45, 0.25))
	car.queue_free()


func test_blocked_car_sidesteps_to_the_free_lane_after_a_while() -> void:
	# Two forward lanes; a parked player blocks the right lane.
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 50, "lf": 2, "w": 7.0}]))
	m.anchors = PackedVector3Array([Vector3.ZERO])
	var right := -1
	for p in m.lanes.paths:
		if p.edge_id == "w1.0" and p.lane_index == 0:
			right = p.id
	var parked: Node3D = auto_free(Node3D.new())
	add_child(parked)
	parked.global_position = m.lanes.paths[right].position_at(120.0)
	m.obstacles = [parked]
	var a := _add_agent(m, right, 60.0, 12.0)
	var waited := false
	for i in range(60 * 22):  # about 4 s to stop, 8 s blocked, then time to pull away
		m.step(1.0 / 60.0)
		if a.speed < 0.3 and a.path_id == right:
			waited = true
	assert_bool(waited).is_true()
	assert_int(a.path_id).is_not_equal(right)
	assert_float(a.distance).is_greater(130.0)
	assert_bool(a.braking).is_false()


func test_sidestep_slides_over_with_the_heading_held_straight() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 50, "lf": 2, "w": 7.0}]))
	m.anchors = PackedVector3Array([Vector3.ZERO])
	var right := -1
	for p in m.lanes.paths:
		if p.edge_id == "w1.0" and p.lane_index == 0:
			right = p.id
	var parked: Node3D = auto_free(Node3D.new())
	add_child(parked)
	parked.global_position = m.lanes.paths[right].position_at(120.0)
	m.obstacles = [parked]
	var a := _add_agent(m, right, 60.0, 12.0)
	var old_z := m.lanes.paths[right].position_at(100.0).z
	var frames := 0
	while a.path_id == right and frames < 60 * 20:
		m.step(1.0 / 60.0)
		frames += 1
	assert_int(a.path_id).is_not_equal(right)
	var new_z := m.lanes.paths[a.path_id].position_at(a.distance).z
	# Just after the sidestep the car is still on its old line, pointing down the road.
	assert_float(a.transform.origin.z).is_equal_approx(old_z, 0.2)
	assert_float((-a.transform.basis.z).dot(Vector3(1, 0, 0))).is_greater(0.99)
	var start_d := a.distance
	while a.distance - start_d < float(m.config["car_length_m"]) and frames < 60 * 40:
		m.step(1.0 / 60.0)
		frames += 1
	# One car length on: between the lanes, still pointing straight.
	assert_float(a.transform.origin.z).is_between(minf(old_z, new_z) + 0.3, maxf(old_z, new_z) - 0.3)
	assert_float((-a.transform.basis.z).dot(Vector3(1, 0, 0))).is_greater(0.99)
	while a.distance - start_d < 3.0 * float(m.config["car_length_m"]) and frames < 60 * 60:
		m.step(1.0 / 60.0)
		frames += 1
	# Three car lengths on: centred in the new lane.
	assert_float(a.transform.origin.z).is_equal_approx(new_z, 0.05)


func _bus(m: TrafficManager, path_id: int, distance: float) -> TrafficAgent:
	var a := _add_agent(m, path_id, distance, 5.0)
	a.kind = TrafficManager.Kind.BUS
	a.vehicle_id = "bus"
	a.length_m = float(VehicleCatalogue.entry("bus")["dims"]["length_m"])
	a.next_stop_d = m._next_stop(path_id, distance)
	return a


func test_cars_keep_out_of_bus_lanes_and_buses_head_for_them() -> void:
	# A feeder splits into a bus-only street (straight on) and an ordinary one (also straight on).
	var g := _graph([
		{"id": "w1.0", "pl": [[-100, 0, 0], [0, 0, 0]]},
		{"id": "w2.0", "pl": [[0, 0, 0], [100, 0, 0]], "bus": "only"},
		{"id": "w3.0", "pl": [[0, 0, 0], [100, 0, 2]]},
	])
	var m := _manager(g)
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var feeder := -1
	for p in m.lanes.paths:
		if p.edge_id == "w1.0":
			feeder = p.id
	var car_lanes := {}
	var bus_lanes := {}
	for trial in range(12):
		m.agents.clear()
		var car := _add_agent(m, feeder, 95.0, 10.0)
		var bus := _bus(m, feeder, 95.0)
		bus.path_id = feeder
		for i in range(300):
			m.step(1.0 / 60.0)
		car_lanes[m.lanes.paths[car.path_id].edge_id] = true
		bus_lanes[m.lanes.paths[bus.path_id].edge_id] = true
	assert_bool(car_lanes.has("w3.0")).override_failure_message("cars never reached the open street: %s" % [car_lanes.keys()]).is_true()
	assert_bool(car_lanes.has("w2.0")).override_failure_message("a car entered the bus lane").is_false()
	assert_bool(bus_lanes.has("w2.0")).override_failure_message("buses never took the bus lane").is_true()
	assert_bool(bus_lanes.has("w3.0")).override_failure_message("a bus left the bus lane for the car lane").is_false()


func test_bus_dwells_at_a_stop_then_carries_on() -> void:
	var g := _graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]], "kph": 50}])
	g.bus_stops.append({"id": "s1", "position": Vector3(200, 0, 0), "edge": "w1.0"})
	var m: TrafficManager = auto_free(TrafficManager.new())
	add_child(m)
	m.setup(LaneGraph.build(g, JunctionBuilder.build_all(g)), g)
	m.enabled = false
	m.anchors = PackedVector3Array([Vector3(200, 0, 0)])  # near: full-rate stepping
	var bus := _bus(m, 0, 150.0)
	assert_float(bus.next_stop_d).is_equal_approx(200.0, 1.0)
	var stood_still := 0.0
	var stood_at := -1.0
	for i in range(60 * 25):
		m.step(1.0 / 60.0)
		if bus.speed < 0.05 and bus.dwell > 0.0:
			stood_still += 1.0 / 60.0
			stood_at = bus.distance
	assert_float(stood_still).is_between(float(m.config["bus_dwell_s"]) - 1.0, float(m.config["bus_dwell_s"]) + 1.0)
	assert_float(stood_at).is_equal_approx(200.0, 2.0)
	assert_float(bus.distance).is_greater(250.0)
	assert_bool(bus.next_stop_d == INF).is_true()


func test_cars_avoid_tunnel_roads_when_another_way_continues() -> void:
	var g := _graph([
		{"id": "w1.0", "pl": [[-100, 0, 0], [0, 0, 0]]},
		{"id": "w2.0", "pl": [[0, 0, 0], [100, 0, 0]], "tunnel": true},
		{"id": "w3.0", "pl": [[0, 0, 0], [100, 0, 2]]},
	])
	var m := _manager(g)
	m.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var feeder := -1
	for p in m.lanes.paths:
		if p.edge_id == "w1.0":
			feeder = p.id
	for trial in range(10):
		m.agents.clear()
		var car := _add_agent(m, feeder, 95.0, 10.0)
		for i in range(300):
			m.step(1.0 / 60.0)
		assert_str(m.lanes.paths[car.path_id].edge_id).is_equal("w3.0")


func _spawn_mix(m: TrafficManager, hour: float, n: int) -> Dictionary:
	m.hour = hour
	m.rng.seed = 99
	var counts := {}
	var spawned := 0
	var tries := 0
	while spawned < n and tries < n * 20:
		tries += 1
		m.agents.clear()
		m._spawn_one()
		if m.agents.is_empty():
			continue
		var id: String = m.agents[0].vehicle_id
		counts[id] = int(counts.get(id, 0)) + 1
		spawned += 1
	return counts


func test_vans_and_trucks_by_day_taxis_by_night_on_an_arterial() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[-200, 0, 0], [200, 0, 0]], "class": "secondary"}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 120)])
	var noon := _spawn_mix(m, 12.0, 800)
	var late := _spawn_mix(m, 22.0, 800)
	var work_noon: int = int(noon.get("van", 0)) + int(noon.get("box_truck", 0))
	var work_late: int = int(late.get("van", 0)) + int(late.get("box_truck", 0))
	assert_int(work_noon).is_greater(work_late * 2)
	assert_int(int(late.get("taxi", 0))).is_greater(int(noon.get("taxi", 0)) * 2)
	assert_int(noon.size()).is_greater_equal(7)  # a real mix, not one hull in eight colours


func test_residential_streets_get_no_buses_and_bus_lanes_only_buses() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[-200, 0, 0], [200, 0, 0]], "class": "residential"}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 120)])
	assert_int(int(_spawn_mix(m, 12.0, 400).get("bus", 0))).is_equal(0)
	var b := _manager(_graph([{"id": "w1.0", "pl": [[-200, 0, 0], [200, 0, 0]], "class": "secondary", "bus": "only"}]))
	b.anchors = PackedVector3Array([Vector3(0, 0, 120)])
	var mix := _spawn_mix(b, 12.0, 50)
	assert_int(int(mix.get("bus", 0))).is_equal(50)


func test_far_cars_draw_at_lod1_and_near_ones_at_lod0() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]]}]))
	var near := _add_agent(m, 0, 10.0, 0.0)
	var far := _add_agent(m, 0, 300.0, 0.0)
	near.vehicle_id = "van"
	far.vehicle_id = "van"
	near.anchor_dist = m.lod0_m - 5.0
	far.anchor_dist = m.lod0_m + 5.0
	assert_str(m.mesh_key(near)).is_equal("van:0")
	assert_str(m.mesh_key(far)).is_equal("van:1")
	m._render()
	assert_int(m._meshes["van:0"].multimesh.visible_instance_count).is_equal(1)
	assert_int(m._meshes["van:1"].multimesh.visible_instance_count).is_equal(1)
	far.anchor_dist = 1.0  # the player drives up to it
	m._render()
	assert_int(m._meshes["van:0"].multimesh.visible_instance_count).is_equal(2)
	assert_int(m._meshes["van:1"].multimesh.visible_instance_count).is_equal(0)


func test_a_busy_class_grows_its_multimesh_instead_of_dropping_cars() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]]}]))
	var cap: int = m._meshes["taxi:1"].multimesh.instance_count
	for i in range(cap + 5):
		var a := _add_agent(m, 0, float(i), 0.0)
		a.vehicle_id = "taxi"
		a.anchor_dist = 500.0
	m._render()
	assert_int(m._meshes["taxi:1"].multimesh.visible_instance_count).is_equal(cap + 5)


func test_pooled_bodies_take_the_vehicles_box_and_mass() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[0, 0, 0], [400, 0, 0]]}]))
	m.anchors = PackedVector3Array([Vector3(10, 0, 0)])
	var a := _add_agent(m, 0, 10.0, 0.0)
	a.vehicle_id = "box_truck"
	a.anchor_dist = 0.0
	m._assign_bodies()
	assert_object(a.body).is_not_null()
	assert_float(a.body.mass).is_equal(float(VehicleCatalogue.entry("box_truck")["mass_kg"]))
	var shape := (a.body.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
	assert_float(shape.size.z).is_equal_approx(float(VehicleCatalogue.entry("box_truck")["dims"]["length_m"]), 0.01)


func test_parking_lanes_are_flagged_and_traffic_never_takes_them() -> void:
	# A street meets a driveway (class parking) and carries on straight.
	var g := _graph([
		{"id": "w1.0", "pl": [[-100, 0, 0], [0, 0, 0]]},
		{"id": "w2.0", "pl": [[0, 0, 0], [100, 0, 0]]},
		{"id": "w3.0", "pl": [[0, 0, 0], [0, 0, 60]], "class": "parking"},
	])
	var m := _manager(g)
	var feeder := -1
	for p in m.lanes.paths:
		if p.edge_id == "w3.0":
			assert_bool(p.parking_only).is_true()
		elif p.edge_id != "":
			assert_bool(p.parking_only).is_false()
		if p.edge_id == "w1.0":
			feeder = p.id
	var into_parking := 0
	for p in m.lanes.paths:
		if p.is_connector and p.next.size() == 1 and m.lanes.paths[p.next[0]].parking_only:
			assert_bool(p.parking_only).is_true()  # the connector into it is flagged too
			into_parking += 1
	assert_int(into_parking).is_greater(0)
	var rng := RandomNumberGenerator.new()
	var feeder_path: LaneGraph.LanePath = m.lanes.paths[feeder]
	for i in range(200):
		var nxt := m.lanes.choose_next(feeder_path, rng)
		assert_bool(m.lanes.paths[nxt].parking_only).is_false()


func test_a_street_ending_in_a_driveway_is_a_dead_end_to_traffic() -> void:
	var g := _graph([
		{"id": "w1.0", "pl": [[-100, 0, 0], [0, 0, 0]]},
		{"id": "w3.0", "pl": [[0, 0, 0], [0, 0, 60]], "class": "parking"},
	])
	var m := _manager(g)
	for p in m.lanes.paths:
		if p.edge_id == "w1.0":
			assert_int(m.lanes.choose_next(p, RandomNumberGenerator.new())).is_equal(-1)


func test_nothing_spawns_on_a_parking_aisle() -> void:
	var m := _manager(_graph([{"id": "w1.0", "pl": [[-200, 0, 0], [200, 0, 0]], "class": "parking"}]))
	m.anchors = PackedVector3Array([Vector3(0, 0, 120)])
	for i in range(200):
		m._spawn_one()
	assert_int(m.agents.size()).is_equal(0)


func test_the_bigger_road_has_priority_at_an_uncontrolled_junction() -> void:
	# #106: highway traffic stopped at its own on-ramp waiting for ramp cars.
	assert_int(TrafficManager.road_rank("motorway")).is_greater(TrafficManager.road_rank("motorway_link"))
	assert_int(TrafficManager.road_rank("primary")).is_greater(TrafficManager.road_rank("residential"))
	assert_int(TrafficManager.road_rank("residential")).is_greater(TrafficManager.road_rank("service"))


func test_a_motorway_car_does_not_wait_for_its_on_ramp_but_the_ramp_waits_for_it() -> void:
	# #106: the merge node, tagged a plain junction, held highway cars for ramp cars.
	var g := _graph([
		{"id": "w1.0", "pl": [[-100, 0, 0], [0, 0, 0]], "class": "motorway", "lf": 2, "lb": 0, "w": 7.0},
		{"id": "w2.0", "pl": [[0, 0, 0], [100, 0, 0]], "class": "motorway", "lf": 2, "lb": 0, "w": 7.0},
		{"id": "w3.0", "pl": [[-100, 0, 30], [0, 0, 0]], "class": "motorway_link", "lf": 1, "lb": 0, "w": 3.5},
	])
	var m := _manager(g)
	var node := ""
	var motor_lane := -1
	var ramp_lane := -1
	for p in m.lanes.paths:
		if p.is_connector:
			continue
		if p.edge_id == "w1.0" and motor_lane < 0:
			motor_lane = p.id
		if p.edge_id == "w3.0":
			ramp_lane = p.id
	for nid in g.nodes:
		if (g.nodes[nid].position as Vector3).length() < 0.1:
			node = nid
	var motor := TrafficAgent.new()
	motor.path_id = motor_lane
	var ramp := TrafficAgent.new()
	ramp.path_id = ramp_lane
	m._claim_junction(ramp, node)
	assert_bool(m._junction_busy(node, motor)).override_failure_message("the motorway car waited for the ramp").is_false()
	m._leave_junction(ramp)
	m._claim_junction(motor, node)
	assert_bool(m._junction_busy(node, ramp)).override_failure_message("the ramp car did not wait for the motorway").is_true()



func test_other_cars_light_the_road_at_night_and_the_nearest_carry_a_light() -> void:
	var g := _graph([{"id": "w1.0", "pl": [[-200, 0, 0], [200, 0, 0]], "lf": 1, "lb": 0, "w": 3.5}])
	var m := _manager(g)
	m.anchors = PackedVector3Array([Vector3.ZERO])
	for x in [-60.0, -20.0, 30.0, 300.0]:  # the last one is beyond the pool reach
		var a := TrafficAgent.new()
		a.transform = Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(x, 0, 0))
		m.agents.append(a)
	m.night = 0.0
	m._render()
	assert_int(m._pool_mmi.multimesh.visible_instance_count).is_equal(0)  # by day: nothing
	assert_bool(m._beams.any(func(l: SpotLight3D) -> bool: return l.visible)).is_false()
	m.night = 1.0
	m._render()
	assert_int(m._pool_mmi.multimesh.visible_instance_count).is_equal(3)
	var lit := m._beams.filter(func(l: SpotLight3D) -> bool: return l.visible)
	assert_int(lit.size()).is_equal(mini(3, m.headlight_lights))
	# The pool sits ahead of its car (the car faces +x).
	var t := m._pool_mmi.multimesh.get_instance_transform(0)
	assert_float(t.origin.x).is_greater(-60.0 + 2.0)
