extends GdUnitTestSuite
## add-police 2.x: routes, cars per star, officers, busted, and the officer weapon by tone.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")

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


func _setup() -> PoliceManager:
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
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	holder.add_child(p)
	p.global_position = Vector3(0, 1, 0)
	var w: Wanted = auto_free(Wanted.new())
	add_child(w)
	var pm: PoliceManager = auto_free(PoliceManager.new())
	pm.wanted = w
	pm.graph = _graph()
	pm.player = p
	pm.holder = holder
	add_child(pm)
	return pm


func test_a_route_follows_the_road() -> void:
	var pm := _setup()
	var r := pm.route(Vector3(395, 0, 1), Vector3(5, 0, 0))
	assert_int(r.size()).is_greater(10)
	assert_float(r[0].x).is_greater(370.0)
	assert_float(r[r.size() - 1].x).is_less(10.0)


func test_cars_come_per_star_and_leave_when_the_level_clears() -> void:
	var pm := _setup()
	pm.wanted.set_stars(2)
	for i in range(5):
		await get_tree().physics_frame
	assert_int(pm.cars.size()).is_equal(2)
	for car in pm.cars:
		assert_object(car.get_node_or_null("LightBar")).is_not_null()
		var d := car.global_position.distance_to(pm.player.global_position)
		assert_float(d).is_between(85.0, 165.0)
	pm.wanted.clear()
	for i in range(3):
		await get_tree().physics_frame
	assert_int(pm.cars.size()).is_equal(0)


func test_standing_still_beside_an_officer_is_busted() -> void:
	var pm := _setup()
	pm.wanted.set_stars(1)
	pm.wanted.config["police_per_star"] = [0, 0, 0, 0]  # just the officer
	var caught := [0]
	pm.busted.connect(func() -> void: caught[0] += 1)
	pm.officers.append(pm._make_officer(pm.player.global_position + Vector3(1.5, 0, 0)))
	await get_tree().create_timer(3.0).timeout  # landing first, then the 2 s hold
	assert_int(caught[0]).is_greater_equal(1)


func test_the_officer_weapon_follows_the_tone() -> void:
	var pm := _setup()
	pm.wanted.config["police_per_star"] = [0, 0, 0, 0]
	var nets := [0]
	var shots := [0]
	pm.net_hit.connect(func(_s: float) -> void: nets[0] += 1)
	pm.shot_at.connect(func(_d: float) -> void: shots[0] += 1)
	ContentMode.set_mode("clean", false)
	pm.wanted.set_stars(1)
	pm.officers.append(pm._make_officer(pm.player.global_position + Vector3(8, 0, 0)))
	for i in range(10):
		await get_tree().physics_frame
	assert_int(nets[0]).is_greater(0)  # clean: a net
	assert_int(shots[0]).is_equal(0)
	ContentMode.set_mode("gritty", false)
	pm._officer_cooldown.clear()
	nets[0] = 0
	for i in range(10):
		await get_tree().physics_frame
	assert_int(shots[0]).is_equal(0)  # gritty below 3 stars: no firing
	pm.wanted.set_stars(3)
	pm._officer_cooldown.clear()
	for i in range(10):
		await get_tree().physics_frame
	assert_int(shots[0]).is_greater(0)


func test_the_helicopter_comes_at_three_stars_and_heads_home_below() -> void:
	var pm := _setup()
	pm.wanted.config["police_per_star"] = [0, 0, 0, 0]
	pm.wanted.set_stars(2)
	for i in range(3):
		await get_tree().physics_frame
	assert_bool(pm.helicopter == null).is_true()
	pm.wanted.set_stars(3)
	for i in range(3):
		await get_tree().physics_frame
	assert_bool(pm.helicopter != null).is_true()
	var y := pm.helicopter.global_position.y - pm.player.global_position.y
	assert_float(y).is_greater(40.0)  # no pad here: it arrives at cruise height
	pm.wanted.set_stars(2)
	await get_tree().physics_frame
	assert_int(pm.helicopter.state).is_equal(PoliceHelicopter.State.RETURN)
	assert_bool(pm.wanted.helicopter_sees).is_false()


func test_a_ceiling_hides_the_player_from_the_helicopter() -> void:
	var pm := _setup()
	var heli: PoliceHelicopter = auto_free(PoliceHelicopter.new())
	pm.holder.add_child(heli)
	heli.state = PoliceHelicopter.State.CHASE
	heli.target = pm.player
	heli.global_position = pm.player.global_position + Vector3(0, 55, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(heli.sees_target()).is_true()
	var slab := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	shape.shape = box
	slab.add_child(shape)
	pm.holder.add_child(slab)
	slab.global_position = pm.player.global_position + Vector3(0, 6, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(heli.sees_target()).is_false()


func test_an_officer_gets_out_at_the_players_stopped_car_and_busts_them() -> void:
	var pm := _setup()
	pm.wanted.config["police_per_star"] = [0, 0, 0, 0]
	var car: VehicleBody3D = auto_free(PoliceManager.CAR_SCENE.instantiate())
	pm.holder.add_child(car)
	car.global_position = Vector3(0, 0.6, 0)
	pm.player.enter_vehicle(car)
	var caught := [0]
	pm.busted.connect(func() -> void: caught[0] += 1)
	pm.wanted.set_stars(1)
	# A patrol car stopped 12 m away: too far to count by itself.
	var cop: VehicleBody3D = auto_free(PoliceManager.CAR_SCENE.instantiate())
	pm.holder.add_child(cop)
	cop.global_position = Vector3(12, 0.6, 0)
	pm.cars.append(cop)
	await get_tree().create_timer(0.5).timeout
	assert_int(pm.officers.size()).is_equal(1)
	await get_tree().create_timer(4.0).timeout  # walks up to the door, then the 2 s hold
	assert_int(caught[0]).is_greater_equal(1)


func test_the_helicopter_searches_where_it_lost_the_player_and_finds_them_by_sight() -> void:
	var pm := _setup()
	var heli: PoliceHelicopter = auto_free(PoliceHelicopter.new())
	pm.holder.add_child(heli)
	heli.state = PoliceHelicopter.State.CHASE
	heli.target = pm.player
	heli.global_position = pm.player.global_position + Vector3(0, 55, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(heli.sees_target()).is_true()
	# The player slips away out of sight range: it circles the last place it saw them.
	pm.player.global_position = Vector3(390, 1, 0)
	await get_tree().create_timer(PoliceHelicopter.LOST_S + 0.3).timeout
	assert_int(heli.state).is_equal(PoliceHelicopter.State.SEARCH)
	assert_bool(heli.sees_target()).is_false()
	assert_float(heli.last_seen.x).is_less(10.0)
	# A tip from the ground moves the search; in sight again, the chase is back on.
	heli.tip(pm.player.global_position)
	heli.global_position = pm.player.global_position + Vector3(0, 55, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(heli.state).is_equal(PoliceHelicopter.State.CHASE)


func test_a_taken_patrol_car_is_handed_over_not_freed() -> void:
	var pm := _setup()
	pm.wanted.set_stars(1)
	for i in range(5):
		await get_tree().physics_frame
	assert_int(pm.cars.size()).is_equal(1)
	var car := pm.cars[0]
	assert_array([Radio.CHATTER, Radio.OFF]).contains([str(car.get("radio_station"))])  # talk radio or nothing
	car.set("driver_peer_id", Players.LOCAL_PEER_ID)
	pm.wanted.config["police_per_star"] = [0, 0, 0, 0]  # no replacement for this test
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(pm.cars.has(car)).is_false()
	pm.wanted.clear()
	await get_tree().physics_frame
	assert_bool(is_instance_valid(car) and not car.is_queued_for_deletion()).is_true()
	auto_free(car)


## Human, 2026-10-06: the minimap showed neither the police nor the helicopter.
func test_the_police_report_their_cars_and_helicopter_for_the_minimap() -> void:
	var pm := _setup()
	pm.wanted.config["police_per_star"] = [0, 0, 0, 0]
	assert_array(pm.markers()).is_empty()
	var cop: VehicleBody3D = auto_free(PoliceManager.CAR_SCENE.instantiate())
	pm.holder.add_child(cop)
	cop.global_position = Vector3(30, 0.6, 0)
	pm.cars.append(cop)
	pm.wanted.set_stars(3)
	for i in range(3):
		await get_tree().physics_frame
	var kinds: Array = pm.markers().map(func(m: Dictionary) -> String: return m["kind"])
	assert_array(kinds).contains(["car", "helicopter"])
	for m: Dictionary in pm.markers():
		if m["kind"] == "car":
			assert_float((m["at"] as Vector3).distance_to(cop.global_position)).is_less(0.01)
