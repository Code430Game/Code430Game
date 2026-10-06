extends GdUnitTestSuite
## add-unarmed-combat: punch and kick timing on empty hands, the jab and kick poses, the leg
## override, reactions in every tone, the wanted report, and officers' fists.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const UPPER_ARM_M := 0.36  # shoulder to elbow (CharacterMesh pivots, height 1)
const FOREARM_M := HeldWeapon.HAND_M
const THIGH_M := 0.42  # hip to knee
const SHIN_M := 0.46  # knee to ankle

var _mode_before: String


func before_test() -> void:
	_mode_before = ContentMode.current


func after_test() -> void:
	ContentMode.set_mode(_mode_before, false)


func _use_mode(mode: String) -> void:
	assert_bool(ContentMode.set_mode(mode, false)).is_true()


func _shooter() -> Shooter:
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(p)
	var s: Shooter = auto_free(Shooter.new())
	s.player = p
	add_child(s)
	s._ensure_held()
	return s


func _manager() -> PedestrianManager:
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


## Lands a punch or kick on the walker in `pair` from a metre to their west.
func _land(s: Shooter, pair: Array, move: String) -> void:
	var at: Vector3 = (pair[0] as Pedestrian).position() + Vector3.UP
	s.hit(s.fist_weapon(move), pair[1], at, Vector3.LEFT, at + Vector3.LEFT)


## Where the end of a two-bone chain lands: `upper` then `lower` rotations (rest frame, bones
## hanging down -Y) over lengths `a` and `b`, from the joint at the origin.
static func _chain_end(upper: Quaternion, lower: Quaternion, a: float, b: float) -> Vector3:
	return upper * (Vector3.DOWN * a + lower * (Vector3.DOWN * b))


# --- 1.1 timing and the hit path ---


func test_a_tap_punches_alternating_hands_and_a_held_release_kicks() -> void:
	var s := _shooter()
	var moves: Array[String] = []
	s.fired.connect(func(w: Dictionary) -> void: moves.append(str(w["move"])))
	s.step_fists(0.016, true)
	s.step_fists(0.1, true)
	s.step_fists(0.016, false)  # a tap: punch on release
	assert_array(moves).contains_exactly(["punch"])
	assert_int(s._punch_side).is_equal(1)  # the other hand next
	assert_bool(s.held.punching()).is_true()
	s._cooldown = 0.0
	s.step_fists(0.016, false)  # nothing held: nothing thrown
	assert_int(moves.size()).is_equal(1)
	var hold := float(s.fists()["kick_hold_s"])
	s.step_fists(0.016, true)
	for i in range(int(hold / 0.05) + 1):
		s.step_fists(0.05, true)
	assert_bool(s.held.chamber).is_true()  # past the threshold the leg draws up
	assert_int(moves.size()).is_equal(1)  # nothing until release
	s.step_fists(0.016, false)
	assert_array(moves).contains_exactly(["punch", "kick"])
	assert_bool(s.held.chamber).is_false()
	assert_bool(s.held.kicking()).is_true()


func test_punches_and_kicks_keep_their_rate() -> void:
	var s := _shooter()
	var f := s.fists()
	assert_bool(s.punch()).is_true()
	assert_bool(s.punch()).is_false()  # still recovering
	assert_float(s._cooldown).is_equal_approx(float(f["punch_rate_s"]), 0.001)
	s._cooldown = 0.0
	assert_bool(s.kick()).is_true()
	assert_float(s._cooldown).is_equal_approx(float(f["kick_rate_s"]), 0.001)
	assert_float(float(f["kick_range_m"])).is_greater(float(f["punch_range_m"]))  # a kick reaches further
	assert_float(float(f["kick_rate_s"])).is_greater(float(f["punch_rate_s"]))


func test_fists_are_only_for_empty_hands() -> void:
	var s := _shooter()
	s.weapons.slot = 1
	assert_dict(s.weapons.current()).is_not_empty()
	assert_bool(s.pull_trigger()).is_true()  # the melee weapon swings as before
	s.weapons.slot = 0
	assert_dict(s.weapons.current()).is_empty()  # empty hands still resolve to nothing in hand
	assert_str(str(s.weapons.impact("fist").get("sound", ""))).is_not_empty()
	var w := s.fist_weapon("punch")
	assert_str(str(w["impact"])).is_equal("fist")
	assert_bool(bool(w["lethal"])).is_false()


# --- 1.2 poses ---


func test_a_jab_reaches_forward_at_shoulder_height_on_either_arm() -> void:
	for side in [0, 1]:
		var upper := HeldWeapon.UPPER if side == 0 else HeldWeapon.UPPER_R
		var fore := HeldWeapon.FORE if side == 0 else HeldWeapon.FORE_R
		var guard := HeldWeapon.jab_pose(side, 0.0)
		var out := HeldWeapon.jab_pose(side, 0.42)
		var back := HeldWeapon.jab_pose(side, 1.0)
		var g := _chain_end(guard[upper], guard[fore], UPPER_ARM_M, FOREARM_M)
		var o := _chain_end(out[upper], out[fore], UPPER_ARM_M, FOREARM_M)
		var b := _chain_end(back[upper], back[fore], UPPER_ARM_M, FOREARM_M)
		# Guard: the fist up near the chin, close to the body.
		assert_float(g.y).override_failure_message("guard height %d" % side).is_greater(-0.15)
		assert_float(g.z).is_greater(-0.45)
		# Out: well ahead, near shoulder height, and in toward the centre line.
		assert_float(o.z).override_failure_message("reach %d" % side).is_less(-0.6)
		assert_float(absf(o.y)).is_less(0.2)
		var shoulder_x := 0.30 if side == 0 else -0.30
		assert_float(absf(shoulder_x + o.x)).override_failure_message("inward %d" % side).is_less(absf(shoulder_x))
		# Back in guard at the end.
		assert_float(b.distance_to(g)).is_less(0.01)


func test_a_jab_keeps_the_other_arm_in_guard() -> void:
	var out := HeldWeapon.jab_pose(0, 0.42)
	var guard := HeldWeapon.jab_pose(1, 0.0)
	assert_float((out[HeldWeapon.UPPER_R] as Quaternion).angle_to(guard[HeldWeapon.UPPER_R])).is_less(0.001)
	assert_float((out[HeldWeapon.FORE_R] as Quaternion).angle_to(guard[HeldWeapon.FORE_R])).is_less(0.001)


func test_a_kick_draws_the_leg_up_snaps_it_out_and_puts_it_down() -> void:
	var rest := HeldWeapon.kick_pose(0.0)
	var drawn := HeldWeapon.kick_pose(0.3)
	var out := HeldWeapon.kick_pose(0.58)
	var down := HeldWeapon.kick_pose(1.0)
	var r := _chain_end(rest[HeldWeapon.THIGH], rest[HeldWeapon.SHIN], THIGH_M, SHIN_M)
	var d := _chain_end(drawn[HeldWeapon.THIGH], drawn[HeldWeapon.SHIN], THIGH_M, SHIN_M)
	var o := _chain_end(out[HeldWeapon.THIGH], out[HeldWeapon.SHIN], THIGH_M, SHIN_M)
	var e := _chain_end(down[HeldWeapon.THIGH], down[HeldWeapon.SHIN], THIGH_M, SHIN_M)
	assert_float(r.y).is_less(-0.85)  # standing
	assert_float(d.y).is_greater(r.y + 0.25)  # foot drawn up under the knee ...
	assert_float(absf(d.z)).is_less(0.35)  # ... not yet out
	assert_float(o.z).is_less(-0.8)  # foot out ahead
	assert_float(o.y).is_greater(-0.3)  # about hip height
	assert_float(e.distance_to(r)).is_less(0.01)


func test_moves_fade_in_and_out_of_the_walk() -> void:
	assert_float(HeldWeapon.move_weight(-1.0)).is_equal(0.0)
	assert_float(HeldWeapon.move_weight(0.0)).is_equal(0.0)
	assert_float(HeldWeapon.move_weight(0.5)).is_equal(1.0)
	assert_float(HeldWeapon.move_weight(1.0)).is_equal(0.0)


func test_the_rig_blends_the_leg_override_on_its_own_weight() -> void:
	var rig: CharacterRig = auto_free(CharacterRig.new())
	rig.profile = CharacterProfile.random()
	add_child(rig)
	var thigh := rig.skeleton.find_bone(HeldWeapon.THIGH)
	var arm := rig.skeleton.find_bone(HeldWeapon.UPPER)
	var raised := Quaternion(Vector3.RIGHT, 1.2)
	rig.leg_override = {HeldWeapon.THIGH: raised}
	rig.bone_override = {HeldWeapon.UPPER: raised}
	rig.override_weight = 0.0
	rig.leg_weight = 1.0
	rig.repose()
	assert_float(rig.skeleton.get_bone_pose_rotation(thigh).angle_to(raised)).is_less(0.001)
	assert_float(rig.skeleton.get_bone_pose_rotation(arm).angle_to(Quaternion.IDENTITY)).is_less(0.001)  # arm untouched
	rig.leg_weight = 0.0
	rig.repose()
	assert_float(rig.skeleton.get_bone_pose_rotation(thigh).angle_to(Quaternion.IDENTITY)).is_less(0.001)


func test_a_held_kick_poses_the_body() -> void:
	var s := _shooter()
	var rig := s.player.rig()
	s.held.kick()
	await get_tree().create_timer(HeldWeapon.KICK_S * 0.45).timeout  # into the snap
	assert_float(rig.leg_weight).is_greater(0.5)
	var thigh := rig.skeleton.find_bone(HeldWeapon.THIGH)
	assert_float(rig.skeleton.get_bone_pose_rotation(thigh).get_angle()).is_greater(0.6)
	await get_tree().create_timer(HeldWeapon.KICK_S).timeout
	assert_bool(s.held.kicking()).is_false()
	assert_float(rig.leg_weight).is_equal(0.0)


# --- 1.3 reactions by tone and the wanted report ---


func test_three_punches_in_clean_shove_and_never_knock_down() -> void:
	_use_mode("clean")
	var s := _shooter()
	s.peds = _manager()
	var pair := _walker(s.peds)
	var a: Pedestrian = pair[0]
	for i in range(3):
		_land(s, pair, "punch")
	assert_int(a.state).is_equal(Pedestrian.State.WALKING)
	assert_float(a.stumble).is_greater(0.0)
	assert_float(a.fleeing).is_greater(0.0)
	_land(s, pair, "kick")
	assert_int(a.state).is_equal(Pedestrian.State.WALKING)  # not even a kick floors anyone in clean
	# Stumbles in place first, then runs off.
	var x0 := a.position().x
	var steps := 0
	while a.stumble > 0.0 and steps < 600:
		assert_float(absf(a.position().x - x0)).is_less(0.05)
		s.peds.step(1.0 / 60.0)
		steps += 1
	assert_int(steps).is_greater(1)
	for i in range(60):
		s.peds.step(1.0 / 60.0)
	assert_float(absf(a.position().x - x0)).is_greater(2.0)


func test_the_third_punch_knocks_down_where_violence_is_allowed() -> void:
	for mode: String in ["gritty", "dystopia"]:
		_use_mode(mode)
		var s := _shooter()
		s.peds = _manager()
		var pair := _walker(s.peds)
		var a: Pedestrian = pair[0]
		_land(s, pair, "punch")
		_land(s, pair, "punch")
		assert_int(a.state).override_failure_message(mode).is_equal(Pedestrian.State.WALKING)
		assert_float(a.stumble).is_greater(0.0)
		_land(s, pair, "punch")
		assert_int(a.state).override_failure_message(mode).is_equal(Pedestrian.State.HIT)


func test_a_slow_streak_starts_over() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.peds = _manager()
	var pair := _walker(s.peds)
	var window := float(s.fists()["combo_window_s"])
	for i in range(4):
		_land(s, pair, "punch")
		s._clock += window + 0.1
	assert_int((pair[0] as Pedestrian).state).is_equal(Pedestrian.State.WALKING)
	assert_int(s._streaks.size()).is_less_equal(1)


func test_one_kick_knocks_down_and_counts_as_assault_where_witnessed() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.peds = _manager()
	var pair := _walker(s.peds)
	var wanted: Wanted = auto_free(Wanted.new())
	add_child(wanted)
	wanted.peds = s.peds
	var seen: Array = []
	s.hit_person.connect(func(a: Pedestrian, w: Dictionary, downed: bool) -> void:
		seen.append([a, str(w["move"]), downed])
		wanted.report("assault_down" if downed else "assault", a.position()))  # as the testbed does
	_walker(s.peds, 20.0)  # a witness ten metres along
	_land(s, pair, "kick")
	assert_int((pair[0] as Pedestrian).state).is_equal(Pedestrian.State.HIT)
	assert_array(seen).contains_exactly([[pair[0], "kick", true]])
	assert_int(wanted.stars).is_equal(int(wanted.config["crimes"]["assault_down"]))


func test_a_shove_in_clean_counts_as_assault() -> void:
	_use_mode("clean")
	var s := _shooter()
	s.peds = _manager()
	var pair := _walker(s.peds)
	var downs: Array[bool] = []
	s.hit_person.connect(func(_a: Pedestrian, _w: Dictionary, downed: bool) -> void: downs.append(downed))
	_land(s, pair, "kick")
	assert_array(downs).contains_exactly([false])


# --- officers ---


func _police() -> PoliceManager:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	holder.add_child(p)
	p.global_position = Vector3(0, 1, 0)
	var w: Wanted = auto_free(Wanted.new())
	add_child(w)
	w.config["police_per_star"] = [0, 0, 0, 0]
	var pm: PoliceManager = auto_free(PoliceManager.new())
	pm.wanted = w
	pm.graph = RoadGraph.from_dict({"nodes": [], "edges": [], "pedestrian_ways": [], "bus_stops": []})
	pm.player = p
	pm.holder = holder
	add_child(pm)
	return pm


func test_officers_use_fists_only_without_a_tone_weapon() -> void:
	_use_mode("gritty")
	var pm := _police()
	var hits: Array[float] = []
	pm.shot_at.connect(func(d: float) -> void: hits.append(d))
	pm.wanted.set_stars(1)
	var o := pm._make_officer(pm.player.global_position + Vector3(1.2, 0, 0))
	pm.officers.append(o)
	for i in range(10):
		await get_tree().physics_frame
	assert_int(hits.size()).is_equal(0)  # a pistol, held below three stars: no fists either
	pm._officer_weapon = {"id": "officer", "variants": {}}  # a tone with no officer weapon
	for i in range(10):
		await get_tree().physics_frame
	assert_int(hits.size()).is_greater(0)
	assert_float(hits[0]).is_equal(float(pm.wanted.config["officer_punch_damage"]))
	var held: HeldWeapon = o.get_meta("held")
	assert_bool(held.punching()).is_true()


func test_a_punch_and_a_kick_go_the_same_way_on_the_body() -> void:
	var s := _shooter()
	var sk := s.player.rig().skeleton
	s.held.hold_move = "punch"
	s.held.hold_t = 0.45
	await get_tree().create_timer(0.2).timeout
	var fore := sk.get_bone_global_pose(sk.find_bone(HeldWeapon.FORE))
	var hand := fore.origin + fore.basis * Vector3.DOWN * FOREARM_M
	s.held.hold_move = "kick"
	s.held.hold_t = 0.58
	await get_tree().create_timer(0.3).timeout
	var shin := sk.get_bone_global_pose(sk.find_bone(HeldWeapon.SHIN))
	var foot := shin.origin + shin.basis * Vector3.DOWN * SHIN_M
	assert_float(hand.z).is_less(-0.5)  # ahead of the body (-Z)
	assert_float(foot.z).is_less(-0.5)
