extends GdUnitTestSuite
## Fixes from the 2026-10-06 code review: the weapon wheel after a cancel, no new crime on
## someone already down, reload and weapon resets, traffic handed back on joining a session,
## takes checked by the host and answered once, stalls for late joiners, people waiting for an
## ambulance, stolen patrol cars, and the paramedics' outcome read from the tone's data.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")

var _mode_before: String


func before_test() -> void:
	_mode_before = ContentMode.current


func after_test() -> void:
	ContentMode.set_mode(_mode_before, false)


func _use_mode(mode: String) -> void:
	assert_bool(ContentMode.set_mode(mode, false)).is_true()


## A shooter on a player, with a wheel.
func _shooter() -> Shooter:
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(p)
	var s: Shooter = auto_free(Shooter.new())
	s.player = p
	s.wheel = auto_free(WeaponWheel.new())
	add_child(s.wheel)
	add_child(s)
	s._ensure_held()
	return s


func _peds() -> PedestrianManager:
	var w := RoadGraph.PedestrianWay.new()
	w.id = "p1"
	w.kind = "sidewalk"
	w.width_m = 2.0
	w.road_class = "footway"
	w.polyline = PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0)])
	var m: PedestrianManager = auto_free(PedestrianManager.new())
	add_child(m)
	m.setup(WalkGraph.build([w] as Array[RoadGraph.PedestrianWay]))
	m.enabled = false
	return m


## A walker on the manager's path with a body the weapons can hit: [Pedestrian, body].
func _walker(m: PedestrianManager, at: float = 10.0) -> Array:
	var a := Pedestrian.new()
	a.path_id = 0
	a.distance = at
	a.speed = 1.3
	a.transform = Transform3D(Basis(), m.walk.paths[0].position_at(at))
	m.agents.append(a)
	var body: PedestrianBody = auto_free(PedestrianManager.BODY_SCENE.instantiate())
	add_child(body)
	body.agent = a
	return [a, body]


func _land(s: Shooter, pair: Array, w: Dictionary) -> void:
	var at: Vector3 = (pair[0] as Pedestrian).position() + Vector3.UP
	s.hit(w, pair[1], at, Vector3.LEFT, at + Vector3.LEFT)


## A straight one-lane road east from the origin, 400 m.
func _traffic() -> TrafficManager:
	var nodes := [
		{"id": "a", "position": [0, 0, 0], "ground_y": 0, "junction_type": "junction"},
		{"id": "b", "position": [400, 0, 0], "ground_y": 0, "junction_type": "junction"},
	]
	var edges := [{
		"id": "w1.0", "from": "a", "to": "b", "polyline": [[0, 0, 0], [400, 0, 0]], "class": "secondary",
		"lanes_forward": 1, "lanes_backward": 0, "oneway": true, "speed_kph": 50, "width_m": 7.0, "layer": 0,
		"bridge": false, "tunnel": false, "name": "w1.0", "osm_way_id": 1, "defaulted_fields": [], "access": null,
		"length_m": 400.0, "bus": "", "bus_lane": -1,
	}]
	var graph := RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": [], "bus_stops": []})
	var m: TrafficManager = auto_free(TrafficManager.new())
	add_child(m)
	m.setup(LaneGraph.build(graph, JunctionBuilder.build_all(graph)))
	m.enabled = false
	return m


# --- the weapon wheel and the shooter ---


func test_a_cancelled_wheel_stays_shut_until_lb_is_let_go() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.step_next(0.0, true)
	s.step_next(0.3, true)
	assert_bool(s.wheel.is_open()).is_true()
	s.wheel.close(false)  # B / Esc with LB still held
	s.step_next(0.05, true)
	s.step_next(0.05, true)
	assert_bool(s.wheel.is_open()).override_failure_message("the wheel reopened under a held LB").is_false()
	s.step_next(0.02, false)
	assert_int(s.weapons.slot).is_equal(0)  # the release after a cancel changes nothing
	s.step_next(0.0, true)
	s.step_next(0.3, true)
	assert_bool(s.wheel.is_open()).is_true()  # a new press opens it again


func test_hitting_someone_already_down_reports_no_new_crime() -> void:
	_use_mode("gritty")
	var s := _shooter()
	var m := _peds()
	s.peds = m
	var reports: Array[bool] = []
	s.hit_person.connect(func(_a: Pedestrian, _w: Dictionary, downed: bool) -> void: reports.append(downed))
	var pair := _walker(m)
	_land(s, pair, s.fist_weapon("kick"))
	assert_array(reports).is_equal([true])
	_land(s, pair, s.fist_weapon("kick"))
	_land(s, pair, s.fist_weapon("punch"))
	s.weapons.slot = 2
	_land(s, pair, s.weapons.current())  # a pistol shot at the body on the ground
	assert_array(reports).override_failure_message("a downed person kept counting as new assaults").is_equal([true])


func test_reload_waits_for_an_empty_round_and_does_not_restart() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.weapons.slot = 2
	assert_bool(s.start_reload()).override_failure_message("reloaded a full magazine").is_false()
	s.weapons.use_round()
	assert_bool(s.start_reload()).is_true()
	var left := s._reload_left
	s._physics_process(0.1)
	assert_bool(s.start_reload()).override_failure_message("a second press restarted the reload").is_false()
	assert_float(s._reload_left).is_less(left)


func test_reset_puts_the_weapons_back_to_rest() -> void:
	_use_mode("gritty")
	var s := _shooter()
	var m := _peds()
	s.peds = m
	s.weapons.slot = 2
	s.weapons.use_round()
	s.start_reload()
	s.wheel.open_wheel()
	s._cooldown = 0.5
	s.weapons.slot = 0
	_land(s, _walker(m), s.fist_weapon("punch"))  # one punch of a streak
	s.reset()
	assert_bool(s.wheel.is_open()).is_false()
	assert_float(s._reload_left).is_equal(0.0)
	assert_float(s._cooldown).is_equal(0.0)
	assert_dict(s._streaks).is_empty()


func test_a_new_weapon_does_not_carry_the_last_ones_swing() -> void:
	var s := _shooter()
	var held := s.held
	held.set_weapon(WeaponSet.resolve(s.weapons.defs[0]))
	held.swing()
	assert_bool(held.swinging()).is_true()
	held.set_weapon(WeaponSet.resolve(s.weapons.defs[1]))
	assert_bool(held.swinging()).is_false()


# --- traffic and co-op takes ---


func test_joining_a_session_hands_every_traffic_body_back() -> void:
	var m := _traffic()
	var a := TrafficAgent.new()
	a.path_id = 0
	a.distance = 50.0
	a.transform = Transform3D(Basis(), m.lanes.paths[0].position_at(50.0))
	m.agents.append(a)
	var body: TrafficCar = m._bodies[0]
	a.body = body
	body.agent = a
	a.occupies_junction = "a"
	m._junction_occupants["a"] = [a]
	m.clear_agents()
	assert_array(m.agents).is_empty()
	assert_object(body.agent).override_failure_message("a body stayed bound to a cleared agent").is_null()
	assert_object(m._free_body()).is_not_null()
	assert_array(m._junction_occupants["a"]).is_empty()


func test_a_crashed_car_is_not_released_for_a_guest() -> void:
	var m: TrafficManager = auto_free(TrafficManager.new())
	add_child(m)
	var a := TrafficAgent.new()
	a.transform = Transform3D(Basis(), Vector3(50, 0, 0))
	a.retired = true
	m.agents = [a]
	assert_dict(m.release_near(Vector3(50, 0, 0))).is_empty()


func test_the_host_grants_takes_only_to_players_in_reach() -> void:
	var peers := {1: {}, 2: {}}
	var car := Vector3(100, 0, 0)
	assert_bool(WorldSync.within_reach(peers, 2, Vector3(104, 0, 0), car, 8.0)).is_true()
	assert_bool(WorldSync.within_reach(peers, 2, Vector3(150, 0, 0), car, 8.0)).is_false()  # too far
	assert_bool(WorldSync.within_reach(peers, 3, Vector3(104, 0, 0), car, 8.0)).is_false()  # not in the session
	assert_bool(WorldSync.within_reach(peers, 1, Vector3(104, 0, 0), car, 8.0)).is_false()  # the host never asks
	assert_bool(WorldSync.within_reach(peers, 2, Vector3.INF, car, 8.0)).is_false()  # body not known yet


func test_a_guest_acts_on_one_grant_per_request() -> void:
	var ws: WorldSync = auto_free(WorldSync.new())
	add_child(ws)
	var granted: Array[Vector3] = []
	ws.take_granted.connect(func(t: Transform3D, _c: Color, _v: String, _s: String) -> void: granted.append(t.origin))
	ws._grant_take(Transform3D(Basis(), Vector3(1, 0, 0)), Color.RED, "sedan", "")
	assert_array(granted).override_failure_message("a grant nobody asked for spawned a car").is_empty()
	ws._take_pending = true  # what request_take sets before the RPC
	ws._grant_take(Transform3D(Basis(), Vector3(2, 0, 0)), Color.RED, "sedan", "")
	ws._grant_take(Transform3D(Basis(), Vector3(3, 0, 0)), Color.RED, "sedan", "")  # a repeat
	assert_array(granted).is_equal([Vector3(2, 0, 0)])
	assert_bool(ws.take_pending()).is_false()


func test_a_late_joiner_learns_the_emptied_stalls() -> void:
	var host_parked: ParkedCars = auto_free(ParkedCars.new())
	host_parked.taken = {"lot2:7": true, "lot1:3": true}
	var host: WorldSync = auto_free(WorldSync.new())
	host.parked = host_parked
	add_child(host)
	var keys := host.taken_stalls()
	assert_array(Array(keys)).is_equal(["lot1:3", "lot2:7"])
	var guest_parked: ParkedCars = auto_free(ParkedCars.new())
	add_child(guest_parked)
	var guest: WorldSync = auto_free(WorldSync.new())
	guest.parked = guest_parked
	add_child(guest)
	guest._stalls_taken(keys)
	assert_bool(guest_parked.taken.has("lot1:3") and guest_parked.taken.has("lot2:7")).is_true()


# --- people waiting for an ambulance ---


func test_someone_waiting_for_an_ambulance_is_not_despawned() -> void:
	var m := _peds()
	m.anchors = PackedVector3Array([Vector3(5000, 0, 0)])  # every player far away
	var waiting := Pedestrian.new()
	waiting.state = Pedestrian.State.DOWN
	waiting.held = true
	waiting.transform = Transform3D(Basis(), Vector3(10, 0, 0))
	var other := Pedestrian.new()
	other.transform = Transform3D(Basis(), Vector3(20, 0, 0))
	m.agents = [waiting, other]
	m._despawn_far()
	assert_array(m.agents).override_failure_message("the person the ambulance is coming for vanished").is_equal([waiting])


func test_a_person_reported_twice_joins_one_call_once() -> void:
	var am: AmbulanceManager = auto_free(AmbulanceManager.new())
	var a := Pedestrian.new()
	a.state = Pedestrian.State.DOWN
	am.report(a)
	am.report(a)
	assert_int(am.calls.size()).is_equal(1)
	assert_int(am.calls[0].people.size()).is_equal(1)


func test_the_paramedics_outcome_comes_from_the_tone_data() -> void:
	var expect := {"clean": "revive", "gritty": "stretcher", "dystopia": "drone"}
	for mode: String in expect:
		_use_mode(mode)
		assert_str(AmbulanceManager.outcome()).override_failure_message(mode).is_equal(str(expect[mode]))
	assert_str(ContentMode.outcome("no_such_system", "fallback")).is_equal("fallback")


# --- stolen patrol cars ---


func test_a_stolen_patrol_car_turns_its_light_bar_off() -> void:
	var pm: PoliceManager = auto_free(PoliceManager.new())
	var car: VehicleBody3D = auto_free(VehicleBody3D.new())
	var bar := Node3D.new()
	bar.name = "LightBar"
	car.add_child(bar)
	car.set_meta("police", true)
	pm.cars.append(car)
	var taken: Array[VehicleBody3D] = []
	pm.taken.connect(func(c: VehicleBody3D) -> void: taken.append(c))
	pm.hand_over(car)
	assert_bool(bar.visible).override_failure_message("the light bar stayed on a stolen car").is_false()
	assert_bool(pm.cars.has(car)).is_false()
	assert_bool(car.has_meta("police")).is_false()
	assert_array(taken).is_equal([car])
