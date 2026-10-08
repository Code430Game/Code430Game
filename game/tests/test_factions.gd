extends GdUnitTestSuite
## add-hostile-gang: factions load as data with a variant per tone, a crew of five and a leader
## spawns on its turf, the threat machine warns then attacks a player it sees in turf and
## leaves them alone outside it, hits on members follow the mode data (down in gritty, tagged
## out in clean, never a lethal weapon in clean), the crew flees when outnumbered and downed
## members respawn, heat rises and drains, member gunfire is the member's crime and an officer
## who saw it fights the crew without touching the player's stars, and a guest mirrors the
## host's members from a snapshot and forwards its hits.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")

var _mode_before: String


func before_test() -> void:
	_mode_before = ContentMode.current


func after_test() -> void:
	ContentMode.set_mode(_mode_before, false)


func _use_mode(mode: String) -> void:
	assert_bool(ContentMode.set_mode(mode, false)).is_true()


class Rig:
	extends RefCounted
	var holder: Node3D
	var player: Player
	var wanted: Wanted
	var police: PoliceManager
	var factions: FactionManager


## A flat floor, a player at the origin, the police and a faction manager with no turf yet.
func _setup(with_police: bool = true) -> Rig:
	var r := Rig.new()
	r.holder = auto_free(Node3D.new())
	add_child(r.holder)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(800, 1, 800)
	shape.shape = box
	floor.add_child(shape)
	r.holder.add_child(floor)
	floor.position = Vector3(0, -0.5, 0)
	r.player = auto_free(PLAYER_SCENE.instantiate())
	r.holder.add_child(r.player)
	r.player.global_position = Vector3(0, 1, 0)
	r.wanted = auto_free(Wanted.new())
	r.wanted.config["police_per_star"] = [0, 0, 0, 0]
	add_child(r.wanted)
	if with_police:
		r.police = auto_free(PoliceManager.new())
		r.police.wanted = r.wanted
		r.police.player = r.player
		r.police.holder = r.holder
		add_child(r.police)
	r.factions = auto_free(FactionManager.new())
	r.factions.holder = r.holder
	r.factions.targets = [r.player]
	r.factions.police = r.police
	r.factions.wanted = r.wanted
	add_child(r.factions)
	if r.police != null:
		r.police.factions = r.factions
	return r


func _steps(r: Rig, n: int, delta: float = 1.0 / 60.0) -> void:
	for i in range(n):
		r.factions._physics_process(delta)


## A tunable the faction's own data would otherwise override.
func _tune(r: Rig, key: String, value: Variant) -> void:
	r.factions.config[key] = value
	for f in r.factions.factions:
		f[key] = value


func test_factions_load_with_a_variant_per_tone_and_five_plus_a_leader() -> void:
	var r := _setup(false)
	var f := r.factions.faction("double-cross")
	assert_str(str(f["id"])).is_equal("double-cross")
	assert_int(int(f["crew"]["members"])).is_equal(5)
	_use_mode("clean")
	assert_str(str(r.factions.variant(f)["tag"])).is_equal("Tag, you're it!")
	assert_bool(bool(r.factions.weapon("gun").get("lethal", true))).is_false()
	_use_mode("gritty")
	assert_bool(bool(r.factions.weapon("gun").get("lethal", false))).is_true()


func test_a_crew_spawns_on_its_turf_with_one_leader_and_stays_home() -> void:
	_use_mode("gritty")
	var r := _setup(false)
	r.player.global_position = Vector3(300, 1, 0)  # well outside
	var i := r.factions.add_turf_around(Vector3(60, 0, 0), 30.0)
	assert_int(r.factions.members.size()).is_equal(6)
	var leaders := 0
	for m in r.factions.members:
		if m.leader:
			leaders += 1
		assert_bool(r.factions.turfs[i].contains(m.global_position, 1.0)).is_true()
		assert_bool(m.weapon.is_empty()).is_false()
	assert_int(leaders).is_equal(1)
	_steps(r, 120)
	assert_int(r.factions.crew_state(i)).is_equal(FactionManager.Crew.PATROL)
	for m in r.factions.members:
		assert_bool(r.factions.turfs[i].contains(m.global_position, 3.0)).is_true()
	assert_float(r.factions.heat(i)).is_equal(0.0)


func test_a_seen_player_in_turf_is_warned_then_attacked_and_hurt_in_gritty() -> void:
	_use_mode("gritty")
	var r := _setup(false)
	var hurt: Array[float] = []
	r.factions.hurt.connect(func(d: float) -> void: hurt.append(d))
	var warnings: Array[String] = []
	r.factions.warned.connect(func(t: String, _at: Vector3) -> void: warnings.append(t))
	r.factions.config["sight_los"] = false
	_tune(r, "warning_s", 0.5)
	var i := r.factions.add_turf_around(Vector3(0, 0, 0), 30.0)
	r.player.global_position = Vector3(5, 1, 0)
	_steps(r, 6)
	assert_int(r.factions.crew_state(i)).is_equal(FactionManager.Crew.ALERT)
	assert_array(warnings).is_equal(["Wrong turf."])
	_steps(r, 60 * 3)
	assert_int(r.factions.crew_state(i)).is_equal(FactionManager.Crew.ATTACK)
	assert_bool(hurt.size() > 0).is_true()
	assert_float(r.factions.heat(i)).is_greater(0.0)


func test_in_clean_the_crew_tags_and_never_hurts() -> void:
	_use_mode("clean")
	var r := _setup(false)
	var hurt: Array[float] = []
	var tagged: Array[int] = []
	r.factions.hurt.connect(func(d: float) -> void: hurt.append(d))
	r.factions.tagged.connect(func(n: int) -> void: tagged.append(n))
	r.factions.config["sight_los"] = false
	_tune(r, "warning_s", 0.2)
	var i := r.factions.add_turf_around(Vector3(0, 0, 0), 30.0)
	r.player.global_position = Vector3(4, 1, 0)
	_steps(r, 60 * 4)
	assert_int(r.factions.crew_state(i)).is_equal(FactionManager.Crew.ATTACK)
	assert_int(hurt.size()).is_equal(0)
	assert_bool(tagged.size() > 0).is_true()
	for m in r.factions.members:
		assert_bool(bool(m.weapon.get("lethal", false))).is_false()


func test_outside_the_turf_nobody_comes() -> void:
	_use_mode("gritty")
	var r := _setup(false)
	r.factions.config["sight_los"] = false
	var i := r.factions.add_turf_around(Vector3(0, 0, 0), 20.0)
	r.player.global_position = Vector3(40, 1, 0)  # 20 m past the edge, within sight
	_steps(r, 60 * 3)
	assert_int(r.factions.crew_state(i)).is_equal(FactionManager.Crew.PATROL)
	for m in r.factions.members:
		assert_bool(r.factions.turfs[i].contains(m.global_position, 3.0)).is_true()


func test_a_hit_member_goes_down_in_gritty_and_tags_out_in_clean_then_respawns() -> void:
	var r := _setup(false)
	_use_mode("gritty")
	_tune(r, "respawn_s", 0.5)
	var i := r.factions.add_turf_around(Vector3(0, 0, 0), 30.0)
	var m := r.factions.members[1]
	var gun := r.factions.weapon("gun")
	var result := ""
	for k in range(6):
		if r.factions.in_fight(m):
			result = r.factions.hit_member(m, gun, m.global_position + Vector3.UP, Vector3(0, 1, 10))
	assert_str(result).is_equal("down")
	assert_int(m.state).is_equal(GangMember.State.DOWN)
	assert_int(r.factions.members.size()).is_equal(5)
	assert_int(r.factions.crew_state(i)).is_equal(FactionManager.Crew.ATTACK)  # a hit wakes the crew
	_steps(r, 60)
	assert_int(r.factions.members.size()).is_equal(6)  # the respawn is in
	_use_mode("clean")
	var m2 := r.factions.members[1]
	var brush := r.factions.weapon("melee")
	result = ""
	for k in range(6):
		if r.factions.in_fight(m2):
			result = r.factions.hit_member(m2, brush, m2.global_position + Vector3.UP, Vector3(0, 1, 10))
	assert_str(result).is_equal("tagged")
	assert_int(m2.state).is_equal(GangMember.State.TAGGED)


func test_the_crew_flees_when_more_than_half_are_down() -> void:
	_use_mode("gritty")
	var r := _setup(false)
	r.factions.config["sight_los"] = false
	_tune(r, "warning_s", 0.1)
	_tune(r, "respawn_s", 600.0)
	var i := r.factions.add_turf_around(Vector3(0, 0, 0), 30.0)
	r.player.global_position = Vector3(3, 1, 0)
	_steps(r, 30)
	assert_int(r.factions.crew_state(i)).is_equal(FactionManager.Crew.ATTACK)
	var gun := r.factions.weapon("gun")
	for k in range(4):
		var m := r.factions.members[0]
		for j in range(6):
			if r.factions.in_fight(m):
				r.factions.hit_member(m, gun, m.global_position + Vector3.UP, Vector3(0, 1, 10))
	_steps(r, 2)
	assert_int(r.factions.crew_state(i)).is_equal(FactionManager.Crew.FLEE)


func test_heat_drains_after_leaving_the_turf() -> void:
	_use_mode("gritty")
	var r := _setup(false)
	r.factions.config["sight_los"] = false
	r.factions.config["heat"] = {"rise_per_s": 1.0, "fall_per_s": 1.0, "out_of_turf_s": 0.5, "car_at": 2.0}
	var f := r.factions.factions[0]
	f.erase("heat")
	var i := r.factions.add_turf_around(Vector3(0, 0, 0), 30.0)
	r.player.global_position = Vector3(5, 1, 0)
	_steps(r, 30)
	assert_float(r.factions.heat(i)).is_greater(0.3)
	r.player.global_position = Vector3(300, 1, 0)
	_steps(r, 60 * 3)
	assert_float(r.factions.heat(i)).is_equal(0.0)
	assert_int(r.factions.crew_state(i)).is_equal(FactionManager.Crew.PATROL)


func test_member_gunfire_is_the_members_crime_and_officers_fight_the_crew() -> void:
	_use_mode("gritty")
	var r := _setup(true)
	r.factions.config["sight_los"] = false
	_tune(r, "warning_s", 0.1)
	r.factions.config["hold_range_m"] = [1.0, 40.0]
	r.factions.config["flee_officers_m"] = 5.0  # the crew would flee the arriving officer; keep them fighting here
	var i := r.factions.add_turf_around(Vector3(0, 0, 0), 30.0)
	for m in r.factions.members:
		m.role_ranged = true
		m.weapon = r.factions.weapon("gun")
	r.player.global_position = Vector3(6, 1, 0)
	var officer := r.police.place_officer(Vector3(0, 0, 20))  # in sight of the turf
	r.wanted.police_positions = PackedVector3Array([officer.global_position])
	_steps(r, 60 * 2)
	assert_int(r.factions.crew_state(i)).is_equal(FactionManager.Crew.ATTACK)
	assert_int(r.wanted.stars).is_equal(0)  # the crew's shots are theirs
	assert_object(r.police.gang_target).is_not_null()
	# The officer steps at the nearest member, not the player.
	var before := officer.global_position
	r.police._physics_process(1.0 / 60.0)
	var member := r.police._nearest_member(before)
	assert_object(member).is_not_null()
	assert_float(officer.global_position.distance_to(member.global_position)).is_less(before.distance_to(member.global_position))


func test_a_guest_mirrors_the_crew_from_a_snapshot_and_forwards_hits() -> void:
	_use_mode("gritty")
	var host := _setup(false)
	var i := host.factions.add_turf_around(Vector3(0, 0, 0), 30.0)
	var guest := _setup(false)
	guest.factions.mirror = true
	var forwarded: Array = []
	guest.factions.on_guest_hit = func(turf: int, seed: int, weapon_id: String, _pos: Vector3, _from: Vector3) -> void:
		forwarded.append([turf, seed, weapon_id])
	guest.factions.setup_turfs(host.factions.turfs)
	var data := host.factions.snapshot(Vector3.ZERO, 500.0)
	assert_int(data.size()).is_equal(6 * FactionManager.SNAPSHOT_STRIDE)
	guest.factions.apply_snapshot(data)
	assert_int(guest.factions.members.size()).is_equal(6)
	var hm := host.factions.members[2]
	var gm := guest.factions.member_by_seed(hm.seed)
	assert_object(gm).is_not_null()
	assert_vector(gm.global_position).is_equal_approx(hm.global_position, Vector3.ONE * 0.01)
	assert_bool(gm.leader).is_equal(hm.leader)
	assert_str(guest.factions.hit_member(gm, host.factions.weapon("gun"), gm.global_position, Vector3.ZERO)).is_equal("sent")
	assert_array(forwarded).is_equal([[i, hm.seed, "gun"]])
	# A member the host dropped vanishes on the guest with the next snapshot.
	host.factions.members.erase(hm)
	hm.queue_free()
	guest.factions.apply_snapshot(host.factions.snapshot(Vector3.ZERO, 500.0))
	assert_int(guest.factions.members.size()).is_equal(5)
