extends GdUnitTestSuite
## add-flyable-helicopter: the police helicopter parked on its pad, taking it (a crime that
## grounds the police air unit), arcade flight that holds when let go, the ceiling and the
## district boundary, landing and getting out, crash outcomes by tone, the streamer's
## look-ahead, and co-op (the replica, a guest's request, a pilot leaving).

const PLAYER_SCENE := preload("res://actors/player/player.tscn")

var _mode_before: String


func before_test() -> void:
	_mode_before = ContentMode.current


func after_test() -> void:
	ContentMode.set_mode(_mode_before, false)


## A world with a wide floor at y 0.
func _world() -> Node3D:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 1, 2000)
	shape.shape = box
	floor.add_child(shape)
	holder.add_child(floor)
	floor.position = Vector3(0, -0.5, 0)
	return holder


func _heli(holder: Node3D, at: Vector3, pilot: int = 0) -> FlyableHelicopter:
	var h := FlyableHelicopter.new()
	holder.add_child(h)
	h.global_transform = Transform3D(Basis(), at)
	h.heading = 0.0
	h.driver_peer_id = pilot
	return h


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _police(holder: Node3D) -> PoliceManager:
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	holder.add_child(p)
	p.global_position = Vector3(0, 1, 0)
	var w: Wanted = auto_free(Wanted.new())
	add_child(w)
	var pm: PoliceManager = auto_free(PoliceManager.new())
	pm.wanted = w
	pm.graph = RoadGraph.from_dict({"nodes": [], "edges": [], "pedestrian_ways": [], "bus_stops": []})
	pm.player = p
	pm.holder = holder
	var pad := Services.Place.new()
	pad.id = "pad1"
	pad.kind = "helipad"
	pad.at = Vector3(30, 0, 0)
	pm.helipads = [pad]
	add_child(pm)
	return pm


# --- flight maths ----------------------------------------------------------------------

func test_letting_go_brakes_to_a_hover() -> void:
	var v := Vector3(30, 0, 0)
	for i in range(240):
		v = FlyableHelicopter.step_horizontal(v, Vector3.ZERO, 9.0, 12.0, 1.0 / 60.0)
	assert_float(v.length()).is_less(0.01)
	# The stick held asks for no more than the top speed.
	var w := Vector3.ZERO
	for i in range(1200):
		w = FlyableHelicopter.step_horizontal(w, Vector3(0, 0, -42.0), 9.0, 12.0, 1.0 / 60.0)
	assert_float(w.length()).is_equal_approx(42.0, 0.01)


func test_nothing_pressed_holds_the_height_and_the_ceiling_stops_a_climb() -> void:
	var cfg := {"climb_mps": 10.0, "descend_mps": 8.0, "lift_spool": 0.8, "ceiling_m": 180.0, "ceiling_push_mps": 4.0}
	assert_float(FlyableHelicopter.desired_vertical(0.0, 50.0, 1.0, cfg)).is_equal(0.0)
	assert_float(FlyableHelicopter.desired_vertical(1.0, 50.0, 1.0, cfg)).is_equal(10.0)
	assert_float(FlyableHelicopter.desired_vertical(-1.0, 50.0, 1.0, cfg)).is_equal(-8.0)
	assert_float(FlyableHelicopter.desired_vertical(1.0, 180.0, 1.0, cfg)).is_equal(0.0)
	assert_float(FlyableHelicopter.desired_vertical(0.0, 190.0, 1.0, cfg)).is_equal(-4.0)
	# The rotor not up to speed yet: no lift.
	assert_float(FlyableHelicopter.desired_vertical(1.0, 0.0, 0.5, cfg)).is_equal(0.0)


func test_a_descent_slows_near_the_ground() -> void:
	assert_float(FlyableHelicopter.soften_descent(-8.0, 50.0)).is_equal(-8.0)
	assert_float(FlyableHelicopter.soften_descent(-8.0, 1.0)).is_equal_approx(-2.2, 0.001)
	assert_float(FlyableHelicopter.soften_descent(-8.0, 0.0)).is_equal(-1.0)
	assert_float(FlyableHelicopter.soften_descent(5.0, 0.0)).is_equal(5.0)


func test_the_boundary_pushes_back_inside() -> void:
	var rect := Rect2(0, 0, 1000, 1000)
	assert_vector(FlyableHelicopter.boundary_push(Vector3(500, 50, 500), rect, 80.0, 0.25)).is_equal(Vector3.ZERO)
	var out := FlyableHelicopter.boundary_push(Vector3(1010, 50, 500), rect, 80.0, 0.25)
	assert_float(out.x).is_less(0.0)
	assert_float(out.z).is_equal(0.0)
	var corner := FlyableHelicopter.boundary_push(Vector3(-20, 50, -20), rect, 80.0, 0.25)
	assert_float(corner.x).is_greater(0.0)
	assert_float(corner.z).is_greater(0.0)
	assert_vector(FlyableHelicopter.boundary_push(Vector3(-500, 0, 0), Rect2(), 80.0, 0.25)).is_equal(Vector3.ZERO)


func test_it_tilts_into_its_motion_and_no_further_than_the_limit() -> void:
	var max_tilt := deg_to_rad(14.0)
	var fwd := FlyableHelicopter.tilt_for(Vector3(0, 0, -42), 42.0, max_tilt)
	assert_float(fwd.x).is_equal_approx(-max_tilt, 0.0001)  # nose down going forward
	assert_float(fwd.y).is_equal(0.0)
	var fast := FlyableHelicopter.tilt_for(Vector3(-200, 0, 0), 42.0, max_tilt)
	assert_float(fast.y).is_equal_approx(max_tilt, 0.0001)
	assert_vector(FlyableHelicopter.tilt_for(Vector3.ZERO, 42.0, max_tilt)).is_equal(Vector2.ZERO)


# --- flying it ---------------------------------------------------------------------------

func test_it_climbs_then_holds_its_height_when_let_go() -> void:
	var world := _world()
	var h := _heli(world, Vector3(0, 0.05, 0), Players.LOCAL_PEER_ID)
	h.engine = 1.0
	h.test_input = {"climb": 1.0}
	await _frames(90)
	var y := h.global_position.y
	assert_float(y).is_greater(5.0)
	h.test_input = {"climb": 0.0, "move": Vector2.ZERO}
	await _frames(60)
	var y2 := h.global_position.y
	await _frames(60)
	assert_float(absf(h.global_position.y - y2)).override_failure_message("drifted from %.2f to %.2f" % [y2, h.global_position.y]).is_less(0.3)


func test_it_flies_forward_at_no_more_than_its_top_speed_and_stops_when_let_go() -> void:
	var world := _world()
	var h := _heli(world, Vector3(0, 30, 0), Players.LOCAL_PEER_ID)
	h.engine = 1.0
	h.test_input = {"move": Vector2(0, -1)}
	await _frames(400)
	assert_float(h.linear_velocity.length()).is_less_equal(h.tun("max_speed_mps") + 0.1)
	assert_float(h.linear_velocity.z).is_less(-30.0)  # forward is -Z
	h.test_input = {"move": Vector2.ZERO}
	await _frames(300)
	assert_float(h.linear_velocity.length()).is_less(0.5)


func test_turning_changes_its_heading() -> void:
	var world := _world()
	var h := _heli(world, Vector3(0, 30, 0), Players.LOCAL_PEER_ID)
	h.engine = 1.0
	h.test_input = {"yaw": 1.0}
	await _frames(60)
	assert_float(h.heading).is_greater(0.3)


# --- landing, getting out, parking ------------------------------------------------------

func test_with_nobody_flying_it_lands_and_parks() -> void:
	var world := _world()
	var h := _heli(world, Vector3(0, 12, 0))
	h.engine = 1.0
	await _frames(600)
	assert_float(h.altitude_m()).is_less(0.5)
	assert_bool(h.is_parked()).override_failure_message("still not parked at %.2f m" % h.altitude_m()).is_true()


func test_getting_out_only_landed_or_hovering_low() -> void:
	var world := _world()
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	world.add_child(p)
	var h := _heli(world, Vector3(0, 30, 0))
	h.engine = 1.0
	p.enter_vehicle(h)
	await _frames(5)
	var refused: Array = []
	p.exit_refused.connect(func(reason: String) -> void: refused.append(reason))
	assert_bool(p.try_exit_vehicle()).is_false()
	assert_array(refused).contains(["land_first"])
	assert_bool(p.is_driving()).is_true()
	h.place_at(Transform3D(Basis(), Vector3(0, 0.05, 0)))
	h.freeze = false
	await _frames(10)
	assert_bool(h.can_exit()).is_true()
	assert_bool(p.try_exit_vehicle()).is_true()
	assert_bool(p.is_driving()).is_false()


func test_getting_in_takes_it_off_its_pad() -> void:
	var world := _world()
	var h := _heli(world, Vector3(0, 0.05, 0))
	h.park()
	assert_bool(h.is_parked()).is_true()
	h.driver_peer_id = Players.LOCAL_PEER_ID
	await _frames(2)
	assert_bool(h.is_parked()).is_false()


# --- crash outcomes by tone -------------------------------------------------------------

func test_in_clean_a_hard_hit_bounces_and_never_wrecks_it() -> void:
	ContentMode.set_mode("clean", false)
	var world := _world()
	var h := _heli(world, Vector3(0, 30, 0), Players.LOCAL_PEER_ID)
	for i in range(10):
		h.hit(40.0, Vector3(0, 0, 1))
	assert_bool(h.disabled).is_false()
	assert_float(h.health).is_equal(h.tun("health"))
	assert_str(FlyableHelicopter.outcome()).is_equal("bounce")


func test_in_gritty_hard_hits_wreck_it_and_it_comes_down() -> void:
	ContentMode.set_mode("gritty", false)
	var world := _world()
	var h := _heli(world, Vector3(0, 20, 0), Players.LOCAL_PEER_ID)
	h.engine = 1.0
	h.hit(20.0, Vector3(0, 0, 1))
	assert_float(h.health).is_less(h.tun("health"))
	assert_bool(h.disabled).is_false()
	for i in range(5):
		h.hit(30.0, Vector3(0, 0, 1))
	assert_bool(h.disabled).is_true()
	h.test_input = {"climb": 1.0}  # the pilot can't hold it up any more
	await _frames(240)
	assert_float(h.altitude_m()).is_less(1.0)


# --- the police and the pad -------------------------------------------------------------

func test_the_helicopter_waits_on_its_pad() -> void:
	var world := _world()
	var pm := _police(world)
	await _frames(2)
	assert_object(pm.parked_helicopter).is_not_null()
	assert_float(pm.parked_helicopter.global_position.distance_to(Vector3(30, 0.05, 0))).is_less(0.1)
	assert_bool(pm.parked_helicopter.is_parked()).is_true()
	assert_bool(pm.air_unit_available()).is_true()


func test_taking_it_is_a_crime_and_grounds_the_air_unit_until_one_is_back() -> void:
	var world := _world()
	var pm := _police(world)
	pm.wanted.config["air_return_s"] = 0.3
	var taken: Array = []
	pm.aircraft_taken.connect(func(heli: FlyableHelicopter) -> void:
		taken.append(heli)
		pm.wanted.report("aircraft_theft", heli.global_position, true))
	await _frames(2)
	var heli := pm.parked_helicopter
	pm.player.enter_vehicle(heli)
	await _frames(2)
	assert_array(taken).has_size(1)
	assert_int(pm.wanted.stars).is_equal(2)
	assert_object(pm.parked_helicopter).is_null()
	assert_bool(pm.air_unit_available()).is_false()
	# Still flown when the time is up: no new one yet.
	await get_tree().create_timer(0.5).timeout
	assert_object(pm.parked_helicopter).is_null()
	# Left behind: a new one is back at the pad.
	heli.driver_peer_id = 0
	pm.player.vehicle = null
	await _frames(3)
	assert_object(pm.parked_helicopter).is_not_null()
	assert_bool(pm.parked_helicopter != heli).is_true()


func test_the_ai_helicopter_lifts_off_from_the_pad_and_parks_again() -> void:
	var world := _world()
	var pm := _police(world)
	pm.wanted.config["police_per_star"] = [0, 0, 0, 0]
	await _frames(2)
	assert_object(pm.parked_helicopter).is_not_null()
	pm.wanted.set_stars(3)
	await _frames(3)
	assert_object(pm.helicopter).is_not_null()
	assert_object(pm.parked_helicopter).is_null()
	pm.reset()
	assert_object(pm.helicopter).is_null()
	assert_object(pm.parked_helicopter).is_not_null()


func test_ground_units_see_an_aircraft_from_further() -> void:
	var world := _world()
	var w: Wanted = auto_free(Wanted.new())
	add_child(w)
	var h := _heli(world, Vector3(0, 60, 0))
	await _frames(3)
	w.target = h
	assert_float(w.sight_m()).is_equal(float(w.config["aircraft_sight_m"]))
	var ground := _heli(world, Vector3(50, 0.05, 0))
	await _frames(3)
	w.target = ground
	assert_float(w.sight_m()).is_equal(float(w.config["police_sight_m"]))


# --- streaming and co-op ----------------------------------------------------------------

func test_the_streamer_looks_ahead_of_a_fast_high_aircraft_within_the_cap() -> void:
	var p := Vector3(100, 80, 100)
	assert_vector(ChunkStreamer.look_ahead(p, Vector3.ZERO, 80.0, 8.0, 1.0, 300.0)).is_equal(p)
	var ahead := ChunkStreamer.look_ahead(p, Vector3(10, -3, 0), 50.0, 8.0, 1.0, 300.0)
	assert_vector(ahead).is_equal_approx(Vector3(230, 80, 100), Vector3(0.01, 0.01, 0.01))
	var capped := ChunkStreamer.look_ahead(p, Vector3(0, 0, -40), 150.0, 8.0, 1.0, 300.0)
	assert_float(capped.distance_to(p)).is_equal_approx(300.0, 0.01)


func test_a_peer_flying_it_shows_as_a_helicopter() -> void:
	var r: RemotePlayer = auto_free(RemotePlayer.new())
	add_child(r)
	r.setup(2, Color.RED)
	r.set_vehicle(RemotePlayer.HELICOPTER_ID, Color.WHITE)
	assert_str(r.vehicle_id()).is_equal("helicopter")
	assert_int(r.find_children("Rotor", "", true, false).size()).is_equal(1)
	r.set_vehicle(VehicleCatalogue.default_player, Color.WHITE)
	await _frames(1)
	assert_int(r.find_children("Rotor", "", true, false).size()).is_equal(0)


func test_a_guests_copy_is_asked_for_not_taken() -> void:
	var world := _world()
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	world.add_child(p)
	p.global_position = Vector3(0, 1, 0)
	var h := _heli(world, Vector3(1.2, 0.05, 0.8))
	h.take_by_request = true
	h.park()
	var asked: Array = []
	p.take_vehicle_requested.connect(func(body: Node3D) -> void: asked.append(body))
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	assert_array(asked).contains([h])
	assert_bool(p.is_driving()).is_false()


func test_a_helicopter_left_by_a_gone_pilot_lands_itself() -> void:
	var world := _world()
	var pm := _police(world)
	await _frames(2)
	var left := pm.leave_helicopter(Transform3D(Basis(), Vector3(-50, 15, 0)))
	assert_int(left.driver_peer_id).is_equal(0)
	assert_bool(left.is_parked()).is_false()
	await _frames(600)
	assert_float(left.altitude_m()).is_less(0.5)
	assert_bool(left.is_parked()).is_true()


## On a roof above them, the police can't walk up and arrest the pilot (on the Mac, landing on
## Police HQ's roof was a bust: officers rose to the helicopter's height).
func test_officers_dont_rise_to_a_helicopter_on_a_roof() -> void:
	var world := _world()
	var pm := _police(world)
	pm.wanted.config["police_per_star"] = [0, 0, 0, 0]
	var roof := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	roof.add_child(shape)
	world.add_child(roof)
	roof.position = Vector3(0, 19.5, 0)
	var h := _heli(world, Vector3(0, 20.05, 0))
	pm.player.enter_vehicle(h)
	pm.wanted.set_stars(1)
	var busted: Array = []
	pm.busted.connect(func() -> void: busted.append(true))
	var o := pm.place_officer(Vector3(4, 0, 0))
	await get_tree().create_timer(3.0).timeout
	assert_float(o.global_position.y).is_less(2.0)
	assert_array(busted).is_empty()


func test_the_rotor_beat_stays_continuous_across_the_phase_wrap() -> void:
	# Advance past several whole turns at an awkward beat rate: no sample jumps more than one step.
	var step := FlyableHelicopter.rotor_phase_step(18.0 * 0.37, 1.0 / Synth.MIX_RATE)
	var phase := 0.0
	var last := sin(phase)
	var worst := 0.0
	for i in range(int(4.0 * TAU / step) + 5):
		phase = FlyableHelicopter.advance_phase(phase, step)
		var v := sin(phase)
		worst = maxf(worst, absf(v - last))
		last = v
	assert_float(phase).is_less(TAU)
	assert_float(worst).is_less(step * 1.01)


func test_a_guest_flying_the_helicopter_keeps_the_pad_empty_until_they_are_gone() -> void:
	# The host frees its replica of a guest's stolen helicopter (WorldSync), so only the pilot
	# peer id says it is still flown; a second police helicopter must not appear meanwhile.
	var world := _world()
	var pm := _police(world)
	pm.wanted.config["air_return_s"] = 0.3
	await _frames(2)
	assert_object(pm.parked_helicopter).is_not_null()
	pm.take_parked_helicopter()
	pm.stolen_helicopter.queue_free()
	pm.guest_pilot_peer = 2
	await get_tree().create_timer(0.5).timeout
	await _frames(2)
	assert_object(pm.parked_helicopter).is_null()
	# The guest leaves mid-flight: the helicopter is left where they were, the pad refills.
	pm.leave_helicopter(Transform3D(Basis(), Vector3(80, 20, 0)))
	assert_int(pm.guest_pilot_peer).is_equal(0)
	await _frames(3)
	assert_object(pm.parked_helicopter).is_not_null()
