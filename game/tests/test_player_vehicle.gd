extends GdUnitTestSuite
## The player's car from the catalogue: it stands on its wheels, carries the entry's mass and
## handling, and taking a traffic car keeps that car's class and colour.


func _floor() -> void:
	var floor: StaticBody3D = auto_free(StaticBody3D.new())
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position.y = -0.5
	floor.add_child(cs)
	add_child(floor)


func _car(id: String, at: Vector3 = Vector3(0, 0.4, 0)) -> VehicleBody3D:
	var car: VehicleBody3D = auto_free(TrafficManager.DRIVABLE_CAR_SCENE.instantiate())
	car.set("vehicle_id", id)
	add_child(car)
	car.global_position = at
	return car


func test_every_class_stands_on_its_wheels_with_its_handling() -> void:
	_floor()
	var cars := {}
	var x := -40.0
	for id: String in ["sedan", "hatchback", "coupe", "suv", "pickup", "van", "box_truck", "taxi", "bus"]:
		cars[id] = _car(id, Vector3(x, 0.4, 0))
		x += 10.0
	for i in range(150):
		await get_tree().physics_frame
	for id: String in cars:
		var car: VehicleBody3D = cars[id]
		var e: Dictionary = VehicleCatalogue.entry(id)
		assert_float(car.global_position.y).override_failure_message("%s origin at %.2f m" % [id, car.global_position.y]).is_between(-0.12, 0.08)
		assert_float(car.global_basis.y.y).override_failure_message("%s not upright" % id).is_greater(0.99)
		assert_float(car.mass).is_equal(float(e["mass_kg"]))
		assert_float(float(car.get("top_speed_kph"))).is_equal(float(e["top_speed_kph"]))
		var touching := 0
		for w in car.get_children():
			if w is VehicleWheel3D and (w as VehicleWheel3D).is_in_contact():
				touching += 1
		assert_int(touching).override_failure_message("%s has %d wheels down" % [id, touching]).is_equal(4)
		assert_float(float(car.get("length_m"))).is_equal(float(e["dims"]["length_m"]))


func _traffic() -> TrafficManager:
	var nodes := [
		{"id": "a", "position": [0.0, 0.0, 0.0], "ground_y": 0, "junction_type": "junction"},
		{"id": "b", "position": [300.0, 0.0, 0.0], "ground_y": 0, "junction_type": "junction"},
	]
	var edges := [{"id": "w1.0", "from": "a", "to": "b", "polyline": [[0.0, 0.0, 0.0], [300.0, 0.0, 0.0]], "class": "secondary",
		"lanes_forward": 1, "lanes_backward": 0, "oneway": true, "speed_kph": 50, "width_m": 7.0, "layer": 0, "bridge": false,
		"tunnel": false, "name": "t", "osm_way_id": 1, "defaulted_fields": [], "access": null, "length_m": 300.0, "bus": "", "bus_lane": -1}]
	var graph := RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": [], "bus_stops": []})
	var m: TrafficManager = auto_free(TrafficManager.new())
	add_child(m)
	m.setup(LaneGraph.build(graph, JunctionBuilder.build_all(graph)))
	m.enabled = false
	return m


func _agent(m: TrafficManager, id: String, d: float, color: Color) -> TrafficAgent:
	var a := TrafficAgent.new()
	a.vehicle_id = id
	a.kind = TrafficManager.Kind.BUS if id == "bus" else TrafficManager.Kind.CAR
	a.color = color
	a.path_id = 0
	a.distance = d
	a.transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), Vector3(d, 0, 0))
	a.anchor_dist = 0.0
	m.agents.append(a)
	return a


func test_taking_a_traffic_van_or_bus_keeps_its_class_and_colour() -> void:
	_floor()
	var m := _traffic()
	m.anchors = PackedVector3Array([Vector3(20, 0, 0)])
	var van := _agent(m, "van", 20.0, Color(0.15, 0.3, 0.6))
	var bus := _agent(m, "bus", 60.0, Color(0.82, 0.12, 0.12))
	m._assign_bodies()
	var taken := m.take_car(van.body)
	auto_free(taken)
	assert_str(str(taken.get("vehicle_id"))).is_equal("van")
	assert_object(taken.get("body_color")).is_equal(Color(0.15, 0.3, 0.6))
	assert_float(taken.mass).is_equal(float(VehicleCatalogue.entry("van")["mass_kg"]))
	var taken_bus := m.take_car(bus.body)
	auto_free(taken_bus)
	assert_str(str(taken_bus.get("vehicle_id"))).is_equal("bus")  # a stolen bus stays a bus


func test_host_release_hands_over_the_vehicle_buses_included() -> void:
	var m := _traffic()
	_agent(m, "bus", 40.0, Color(0.82, 0.12, 0.12))
	var got := m.release_near(Vector3(40, 0, 0))
	assert_str(str(got.get("vehicle", ""))).is_equal("bus")
	assert_int(m.agents.size()).is_equal(0)


func test_remote_replica_builds_the_vehicle_it_is_told() -> void:
	var r: RemotePlayer = auto_free(RemotePlayer.new())
	add_child(r)
	r.setup(2, Color.WHITE)
	assert_str(r.vehicle_id()).is_equal(VehicleCatalogue.default_player)
	r.set_vehicle("box_truck", Color(0.9, 0.9, 0.9))
	assert_str(r.vehicle_id()).is_equal("box_truck")
	var shape := (r._car_shape.shape as BoxShape3D)
	assert_float(shape.size.z).is_equal_approx(float(VehicleCatalogue.entry("box_truck")["dims"]["length_m"]), 0.01)


## Seconds from rest to 60 km/h at full throttle, then metres from 60 km/h to a stop braking.
func _accel_and_brake(id: String, at: Vector3) -> Vector2:
	var car := _car(id, at)
	car.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), at)
	for i in range(60):
		await get_tree().physics_frame  # settle on the wheels
	var t := 0.0
	while float(car.call("forward_speed")) * 3.6 < 60.0 and t < 30.0:
		car.set("override_throttle", 1.0)
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var start := car.global_position
	var guard := 0
	while float(car.call("forward_speed")) > 0.3 and guard < 60 * 30:
		car.set("override_throttle", 0.0)
		car.set("override_brake", 1.0)
		await get_tree().physics_frame
		guard += 1
	return Vector2(t, car.global_position.distance_to(start))


func test_hatchback_suv_and_box_truck_handle_differently() -> void:
	_floor()
	var hatch := await _accel_and_brake("hatchback", Vector3(-80, 0.1, -60))
	var suv := await _accel_and_brake("suv", Vector3(-80, 0.1, 0))
	var truck := await _accel_and_brake("box_truck", Vector3(-80, 0.1, 60))
	print("handling: 0-60 km/h s, 60-0 m: hatchback %.1f s %.1f m, suv %.1f s %.1f m, box truck %.1f s %.1f m" % [hatch.x, hatch.y, suv.x, suv.y, truck.x, truck.y])
	assert_float(truck.x).is_greater(hatch.x * 1.3)  # the truck is slow off the line
	assert_float(truck.y).is_greater(hatch.y)  # and takes longer to stop
	assert_float(suv.x).is_not_equal(hatch.x)
