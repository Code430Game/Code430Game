class_name FactionManager
extends Node
## Hostile factions (add-hostile-gang): crews that hold turf, recognise the player there and
## come for them. Factions are data (`factions.v0.json`, base plus pack), turf comes from the
## map pack (`turf.v0.json`), and every decision runs on the host; guests mirror members from
## snapshots and send their hits to the host.
##
## Approach: each turf gets one crew (the faction's members plus a leader) built like police
## officers (rig, weapon in hand, a hittable capsule). A crew has one state the members
## follow: patrol -> alert (a warning while a member sees the player in turf) -> attack
## (the nearest `melee_count` close in, the rest hold at range and fire) -> flee (outnumbered,
## a hurt member, or officers arriving) -> regroup at the centre -> patrol. Members hit by the
## player react from the mode data (`outcomes.gang`): knocked down, or tagged out where the
## tone has no violence; downed members return after `respawn_s`. Heat per turf rises while
## the crew sees the player there, drains after they have been out for a while, and at full
## sends the faction car at the player once. Member crimes an officer can see are reported as
## the member's, so the police come for the gang, never raising the player's stars.

signal hurt(damage: float)  ## a member landed a lethal hit on the local player
signal tagged(count: int)  ## a non-lethal hit (paint, water) marked the local player; the running count
signal warned(text: String, at: Vector3)  ## the crew's shout at the start of a warning
signal member_down(at: Vector3)
signal car_sent(car: VehicleBody3D)

const CONFIG_PATH := "res://actors/factions/faction_config.json"
const FACTIONS_PATH := "res://core/content/factions.v0.json"
const CAR_SCENE := preload("res://actors/vehicles/placeholder_car.tscn")
const SNAPSHOT_STRIDE := 10
const LOSE_S := 8.0  # attack ends this long after the crew last saw the player in turf
const CAR_TIMEOUT_S := 40.0
const REPLAN_S := 2.0
const STEER_GAIN := 1.6

enum Crew { PATROL, ALERT, ATTACK, FLEE, REGROUP }

var config: Dictionary = {}
var factions: Array[Dictionary] = []
var turfs: Array[Turf] = []
var holder: Node3D  # where members and the car live (the world)
var targets: Array[Node3D] = []  # players the crew may go for; the first is the local player
var graph: RoadGraph
var walk: WalkGraph
var police: PoliceManager
var wanted: Wanted
var peds: PedestrianManager
var effects: CombatEffects
var mirror: bool = false  # guest: members come from snapshots, nothing is simulated
var on_guest_hit: Callable = Callable()  # guest: forwards a hit to the host (turf, seed, weapon, pos, from)
var log_turf: bool = false
var members: Array[GangMember] = []
var downed: Array[GangMember] = []
var tags: int = 0  # non-lethal hits on the local player since the last reset
var _crews: Array[Dictionary] = []  # per turf: state, t, alert_t, lost_t, heat, out_t, car_sent, car, respawns
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()
var _weapons: Array[Dictionary] = []
var _weapon_set: WeaponSet
var _log_s: float = 0.0
var _plan: Dictionary = {}  # the car's route plan
var _next_seed: int = 1


func _ready() -> void:
	_rng.seed = 430
	load_data()


## Reads the config and the base factions, then a pack's factions on top (same id replaces).
func load_data(pack_dir: String = "") -> void:
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	config = cfg if cfg is Dictionary else {}
	factions = []
	_merge_factions(FACTIONS_PATH)
	if pack_dir != "":
		_merge_factions(pack_dir.path_join("factions.v0.json"))
	_weapon_set = WeaponSet.new()
	_weapons = _weapon_set.defs


func _merge_factions(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		return
	for f: Dictionary in data.get("factions", []):
		var replaced := false
		for i in range(factions.size()):
			if factions[i].get("id", "") == f.get("id", ""):
				factions[i] = f
				replaced = true
		if not replaced:
			factions.append(f)


## The faction `id`, or the first one when `id` is empty or unknown.
func faction(id: String) -> Dictionary:
	for f in factions:
		if f.get("id", "") == id:
			return f
	return factions[0] if not factions.is_empty() else {}


func faction_index(id: String) -> int:
	for i in range(factions.size()):
		if factions[i].get("id", "") == id:
			return i
	return 0


## A tunable: the faction's own value when it has one, else the config's.
func tun(f: Dictionary, key: String, fallback: Variant) -> Variant:
	if f.has(key):
		return f[key]
	return config.get(key, fallback)


func heat_tun(f: Dictionary, key: String, fallback: float) -> float:
	var h: Dictionary = f.get("heat", {})
	if h.has(key):
		return float(h[key])
	return float((config.get("heat", {}) as Dictionary).get(key, fallback))


## The faction's variant for the active tone (name, weapons, tag).
func variant(f: Dictionary) -> Dictionary:
	return ContentMode.pick_variant(f)


## The weapon definition `id` resolved for the tone, or {} when the tone allows none.
func weapon(id: String) -> Dictionary:
	for w in _weapons:
		if w.get("id", "") == id:
			return WeaponSet.resolve(w)
	return {}


## Takes the pack's turfs and raises a crew in each (host); guests only keep the turfs.
func setup_turfs(list: Array[Turf]) -> void:
	turfs = list
	_crews = []
	for t in turfs:
		_crews.append(_new_crew())
		t.ground_y = _ground_y(Vector3(t.centre.x, t.ground_y, t.centre.y), t.ground_y)
	if not mirror:
		for i in range(turfs.size()):
			spawn_crew(i)


func _new_crew() -> Dictionary:
	return {"state": Crew.PATROL, "t": 0.0, "alert_t": 0.0, "lost_t": 0.0, "heat": 0.0, "out_t": 0.0, "car_sent": false, "car": null, "car_t": 0.0, "respawns": []}


## Adds a square turf of `half` metres around `at` for the first faction and raises its crew
## (the testbed's --gang=N with N members, tests).
func add_turf_around(at: Vector3, half: float, member_count: int = -1) -> int:
	var t := Turf.square(at, half, factions[0].get("id", "") if not factions.is_empty() else "")
	turfs.append(t)
	_crews.append(_new_crew())
	var i := turfs.size() - 1
	if not mirror:
		spawn_crew(i, member_count)
	return i


## The crew of turf `i`: the faction's members and a leader, placed about the turf.
func spawn_crew(i: int, member_count: int = -1) -> void:
	var t := turfs[i]
	var f := faction(t.faction)
	if f.is_empty():
		return
	var count := member_count if member_count >= 0 else int((f.get("crew", {}) as Dictionary).get("members", 5))
	count = mini(count, int(config.get("cap_per_turf", 8)))
	for k in range(count + 1):
		var leader := k == 0
		var at := home(t) if leader else _waypoint(t)
		_make_member(f, i, leader, at, _next_seed)
		_next_seed += 1


## Where the crew gathers: the walk-graph point nearest the turf's centre when the pack has
## one (the centre of a built block sits inside a building), else the centre itself.
func home(t: Turf) -> Vector3:
	var c := Vector3(t.centre.x, t.ground_y, t.centre.y)
	if walk == null:
		return c
	var best := c
	var best_d := INF
	for p in walk.paths_near(c, maxf(t.bounds().size.x, t.bounds().size.y) * 0.6):
		for q in p.points:
			if t.contains(q, 2.0) and q.distance_to(c) < best_d:
				best_d = q.distance_to(c)
				best = q
	return best


func _make_member(f: Dictionary, turf_i: int, leader: bool, at: Vector3, seed: int) -> GangMember:
	var m := GangMember.new()
	m.name = "GangMember%d" % seed
	m.faction_id = str(f.get("id", ""))
	m.faction_index = faction_index(m.faction_id)
	m.turf_index = turf_i
	m.leader = leader
	m.seed = seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 13
	var p := CharacterProfile.random(rng)
	var look: Dictionary = f.get("look", {})
	for key in ["top", "bottom", "jacket", "jacket_colour", "hat"]:
		if look.has(key):
			p[key] = int(look[key])
	if leader and look.has("leader_hat"):
		p["hat"] = int(look["leader_hat"])
	m.rig = CharacterRig.new()
	m.rig.profile = p
	m.add_child(m.rig)
	m.toughness = float(tun(f, "toughness", 100.0)) * (float((f.get("crew", {}) as Dictionary).get("leader_health", 2.0)) if leader else 1.0)
	m.hp = m.toughness
	var v := variant(f)
	var share := float(v.get("ranged_share", 0.34))
	m.role_ranged = str(v.get("ranged", "")) != "" and (leader or rng.randf() < share)
	m.held = HeldWeapon.new()
	m.held.name = "HeldWeapon"
	m.held.rig = m.rig
	m.add_child(m.held)
	m.weapon = weapon(str(v.get("ranged" if m.role_ranged else "melee", "")))
	m.held.set_weapon(m.weapon)
	m.body = FactionBody.new(float(config.get("body_radius_m", 0.32)), float(config.get("body_height_m", 1.8)))
	m.body.member = m
	m.add_child(m.body)
	if mirror:
		m.body.disable()  # a guest's replica: the host adjudicates hits
	holder.add_child(m)
	m.global_position = at
	m.goal = Vector3.INF
	members.append(m)
	return m


## ---- the host's step ----


func _physics_process(delta: float) -> void:
	if mirror or holder == null or turfs.is_empty() or get_tree().paused:
		return
	_clock += delta
	var target := _nearest_target()
	for i in range(turfs.size()):
		_step_crew(i, target, delta)
	for m in members.duplicate():
		if not is_instance_valid(m):
			members.erase(m)
			continue
		_step_member(m, target, delta)
	for m in downed.duplicate():
		_step_out_of_action(m, delta)
	_step_respawns(delta)
	_step_car(target, delta)
	if log_turf:
		_log_s += delta
		if _log_s >= 1.0:
			_log_s = 0.0
			for i in range(turfs.size()):
				var c := _crews[i]
				var states := {}
				for m in members:
					if m.turf_index == i:
						states[m.state_name()] = int(states.get(m.state_name(), 0)) + 1
				print("turf %s: crew %s heat %.2f members %s downed %d" % [turfs[i].id, Crew.keys()[c["state"]].to_lower(), c["heat"], states, downed.size()])


func _nearest_target() -> Node3D:
	var best: Node3D = null
	for t in targets:
		if is_instance_valid(t):
			best = t
			break
	return best


func crew_state(i: int) -> int:
	return int(_crews[i]["state"])


func heat(i: int) -> float:
	return float(_crews[i]["heat"])


## The highest heat of any turf the local player is in or draining from (the HUD).
func heat_shown() -> float:
	var h := 0.0
	for c in _crews:
		h = maxf(h, float(c["heat"]))
	return h


func in_turf(p: Vector3) -> bool:
	for t in turfs:
		if t.contains(p):
			return true
	return false


func _crew_members(i: int, fighting_only: bool = true) -> Array[GangMember]:
	var out: Array[GangMember] = []
	for m in members:
		if m.turf_index == i and (not fighting_only or m.in_fight()):
			out.append(m)
	return out


func _set_crew(i: int, state: int) -> void:
	var c := _crews[i]
	if int(c["state"]) == state:
		return
	c["state"] = state
	c["t"] = 0.0
	for m in _crew_members(i):
		_set_state(m, _member_state_for(state))
		if state == Crew.PATROL:
			m.goal = Vector3.INF


static func _member_state_for(crew: int) -> int:
	match crew:
		Crew.ALERT:
			return GangMember.State.ALERT
		Crew.ATTACK:
			return GangMember.State.ATTACK
		Crew.FLEE:
			return GangMember.State.FLEE
		Crew.REGROUP:
			return GangMember.State.REGROUP
	return GangMember.State.PATROL


func _step_crew(i: int, target: Node3D, delta: float) -> void:
	var c := _crews[i]
	var t := turfs[i]
	var f := faction(t.faction)
	c["t"] = float(c["t"]) + delta
	var crew := _crew_members(i)
	var inside := target != null and t.contains(target.global_position, float(config.get("turf_margin_m", 6.0)))
	var seen := false
	if target != null and inside:
		for m in crew:
			if _sees(m, target):
				seen = true
				break
	# Heat.
	if seen:
		c["heat"] = minf(float(c["heat"]) + heat_tun(f, "rise_per_s", 0.12) * delta, 1.0)
		c["out_t"] = 0.0
	elif not inside:
		c["out_t"] = float(c["out_t"]) + delta
		if float(c["out_t"]) >= heat_tun(f, "out_of_turf_s", 12.0):
			c["heat"] = maxf(float(c["heat"]) - heat_tun(f, "fall_per_s", 0.08) * delta, 0.0)
			if float(c["heat"]) <= 0.0:
				c["car_sent"] = false
	if float(c["heat"]) >= float((config.get("heat", {}) as Dictionary).get("car_at", 1.0)) and not bool(c["car_sent"]) and target != null:
		c["car_sent"] = true
		_send_car(i, target)
	# The crew's state.
	var state := int(c["state"])
	match state:
		Crew.PATROL:
			if seen:
				c["alert_t"] = 0.0
				_set_crew(i, Crew.ALERT)
				warned.emit(str(variant(f).get("tag", "")), crew[0].global_position if not crew.is_empty() else Vector3.ZERO)
		Crew.ALERT:
			if not inside:
				_set_crew(i, Crew.PATROL)
			else:
				c["alert_t"] = float(c["alert_t"]) + delta
				if float(c["alert_t"]) >= float(tun(f, "warning_s", 2.0)):
					_set_crew(i, Crew.ATTACK)
		Crew.ATTACK:
			c["lost_t"] = 0.0 if (seen or (inside and _any_near(crew, target, 12.0))) else float(c["lost_t"]) + delta
			if _should_flee(i, crew, f):
				_set_crew(i, Crew.FLEE)
			elif float(c["lost_t"]) >= LOSE_S:
				_set_crew(i, Crew.REGROUP)
		Crew.FLEE:
			if _all_home(crew, t) or float(c["t"]) > 20.0:
				_set_crew(i, Crew.REGROUP)
		Crew.REGROUP:
			if float(c["t"]) >= float(config.get("regroup_s", 4.0)):
				_set_crew(i, Crew.PATROL)


func _any_near(crew: Array[GangMember], target: Node3D, r: float) -> bool:
	if target == null:
		return false
	for m in crew:
		if m.global_position.distance_to(target.global_position) <= r:
			return true
	return false


func _all_home(crew: Array[GangMember], t: Turf) -> bool:
	var h := home(t)
	for m in crew:
		if m.global_position.distance_to(h) > 6.0:
			return false
	return true


## Flee when fewer than `flee_group_share` of the crew still stands, when any member is hurt
## under `flee_health`, or when officers are within `flee_officers_m`.
func _should_flee(i: int, crew: Array[GangMember], f: Dictionary) -> bool:
	var total := _crew_members(i, false).size() + _respawning(i)
	if total > 0 and float(crew.size()) / float(total) < float(config.get("flee_group_share", 0.5)):
		return true
	for m in crew:
		if m.hp < m.toughness * float(tun(f, "flee_health", 0.3)):
			return true
	if police != null:
		var r := float(config.get("flee_officers_m", 40.0))
		for o in police.officers:
			if is_instance_valid(o) and not crew.is_empty() and o.global_position.distance_to(crew[0].global_position) <= r:
				return true
	return false


func _respawning(i: int) -> int:
	var n := 0
	for r: Dictionary in _crews[i]["respawns"]:
		n += 1
	return n


## True when member `m` can see `target`: inside the turf, within sight, and nothing solid
## between them (a ray on the world layer).
func _sees(m: GangMember, target: Node3D) -> bool:
	var f := faction(m.faction_id)
	var d := m.global_position.distance_to(target.global_position)
	if d > float(tun(f, "sight_m", 28.0)):
		return false
	if not bool(config.get("sight_los", true)) or not m.is_inside_tree():
		return true
	var from := m.global_position + Vector3.UP * 1.5
	var to := target.global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var res := m.get_world_3d().direct_space_state.intersect_ray(q)
	return res.is_empty()


func _set_state(m: GangMember, state: int) -> void:
	if m.state == state:
		return
	m.state = state
	m.state_t = 0.0
	if state == GangMember.State.ALERT:
		_hold_pose(m, _hand_up_pose(), {})
	elif state == GangMember.State.PATROL or state == GangMember.State.ATTACK or state == GangMember.State.FLEE or state == GangMember.State.REGROUP:
		if m.stagger_t <= 0.0:
			_release_pose(m)
	if m.held != null:
		m.held.aiming = false


## ---- members ----


func _step_member(m: GangMember, target: Node3D, delta: float) -> void:
	if m.in_car:
		return
	m.state_t += delta
	m.cooldown -= delta
	if _step_stagger(m, delta):
		return
	var t := turfs[m.turf_index]
	var f := faction(m.faction_id)
	match m.state:
		GangMember.State.PATROL:
			_patrol(m, t, delta)
		GangMember.State.ALERT:
			if target != null:
				_face(m, target.global_position)
			m.rig.advance(delta, 0.0)
		GangMember.State.ATTACK:
			if target != null:
				_attack(m, target, f, delta)
			else:
				m.rig.advance(delta, 0.0)
		GangMember.State.FLEE:
			_go_to(m, home(t), float(config.get("run_speed_mps", 4.0)), delta)
		GangMember.State.REGROUP:
			var h := home(t)
			if m.global_position.distance_to(h) > 2.5:
				_go_to(m, h, float(config.get("patrol_speed_mps", 1.4)), delta)
			else:
				m.rig.advance(delta, 0.0)


func _patrol(m: GangMember, t: Turf, delta: float) -> void:
	if m.pause_t > 0.0:
		m.pause_t -= delta
		m.rig.advance(delta, 0.0)
		return
	if m.goal == Vector3.INF or m.global_position.distance_to(m.goal) <= float(config.get("waypoint_reach_m", 1.5)):
		if m.goal != Vector3.INF:
			var pause: Array = config.get("patrol_pause_s", [1.0, 4.0])
			m.pause_t = _rng.randf_range(float(pause[0]), float(pause[1]))
		m.goal = _waypoint(t)
		return
	_go_to(m, m.goal, float(config.get("patrol_speed_mps", 1.4)), delta)


## A patrol waypoint: a walk-graph point inside the turf when the pack has one near, else a
## random point in the ring.
func _waypoint(t: Turf) -> Vector3:
	if walk != null:
		var r := maxf(t.bounds().size.x, t.bounds().size.y) * 0.6
		var paths := walk.paths_near(Vector3(t.centre.x, t.ground_y, t.centre.y), r)
		var inside := PackedVector3Array()
		for p in paths:
			for q in p.points:
				if t.contains(q):
					inside.append(q)
		if inside.size() > 0:
			return inside[_rng.randi_range(0, inside.size() - 1)]
	var q := t.random_point(_rng)
	return Vector3(q.x, t.ground_y, q.y)


func _go_to(m: GangMember, goal: Vector3, speed: float, delta: float) -> void:
	var step := goal - m.global_position
	step.y = 0.0
	var d := step.length()
	if d < 0.05:
		m.rig.advance(delta, 0.0)
		return
	var move := step.normalized() * minf(speed * delta, d)
	m.global_position += move
	m.global_position.y = lerpf(m.global_position.y, goal.y, clampf(delta * 6.0, 0.0, 1.0))
	_face(m, goal)
	m.rig.advance(delta, speed)


func _face(m: GangMember, at: Vector3) -> void:
	var flat := Vector3(at.x, m.global_position.y, at.z)
	if flat.distance_to(m.global_position) > 0.1:
		m.look_at(flat, Vector3.UP)  # bodies face -Z, toward the target


## The attack: the nearest `melee_count` members of the crew close to melee range and swing;
## the rest hold at range and fire the ranged variant when they carry it, closing otherwise.
func _attack(m: GangMember, target: Node3D, f: Dictionary, delta: float) -> void:
	var d := m.global_position.distance_to(target.global_position)
	var close := _is_closer(m, target)
	var w := m.weapon
	var ranged := m.role_ranged and not w.is_empty() and str(w.get("mechanic", "")) != "melee"
	if ranged and not close:
		var hold: Array = config.get("hold_range_m", [7.0, 14.0])
		if d > float(hold[1]):
			_go_to(m, target.global_position, float(config.get("run_speed_mps", 4.0)), delta)
		elif d < float(hold[0]):
			var away := m.global_position - target.global_position
			away.y = 0.0
			_go_to(m, m.global_position + away.normalized() * 3.0, float(config.get("patrol_speed_mps", 1.4)), delta)
			_face(m, target.global_position)
		else:
			_face(m, target.global_position)
			m.rig.advance(delta, 0.0)
		m.held.aiming = d <= float(config.get("fire_range_m", 24.0))
		if m.cooldown <= 0.0 and d <= float(config.get("fire_range_m", 24.0)) and _sees(m, target) and not _friend_in_line(m, target):
			_fire(m, target, f, w)
		return
	# Melee: close in and swing.
	var reach := float(config.get("melee_range_m", 1.6))
	if d > reach:
		_go_to(m, target.global_position, float(config.get("run_speed_mps", 4.0)), delta)
	else:
		_face(m, target.global_position)
		m.rig.advance(delta, 0.0)
		if m.cooldown <= 0.0:
			_swing(m, target, f, w)


## The `melee_count` members nearest the target go in; the others hold.
func _is_closer(m: GangMember, target: Node3D) -> bool:
	var crew := _crew_members(m.turf_index)
	crew.sort_custom(func(a: GangMember, b: GangMember) -> bool: return a.global_position.distance_to(target.global_position) < b.global_position.distance_to(target.global_position))
	var n := int(config.get("melee_count", 2))
	for k in range(mini(n, crew.size())):
		if crew[k] == m:
			return true
	return false


## True when another member stands between `m` and the target (nobody fires through a friend).
func _friend_in_line(m: GangMember, target: Node3D) -> bool:
	var a := m.position_xz()
	var b := Vector2(target.global_position.x, target.global_position.z)
	for o in _crew_members(m.turf_index):
		if o == m:
			continue
		var p := o.position_xz()
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < 0.8:
			return true
	return false


func _fire(m: GangMember, target: Node3D, f: Dictionary, w: Dictionary) -> void:
	m.cooldown = float(config.get("fire_rate_s", 1.4))
	m.held.recoil()
	var lethal := bool(w.get("lethal", false)) and ContentMode.flag("lethal_weapons")
	if effects != null:
		var muzzle := m.held.muzzle() if m.held.muzzle() != Vector3.INF else m.global_position + Vector3.UP * 1.4
		effects.flash(muzzle, Color(0.4, 0.9, 1.0) if str(w.get("impact", "")) == "energy" else Color(1.0, 0.85, 0.5))
		effects.sound(str(_weapon_set.impact(str(w.get("impact", ""))).get("sound", "")))
	_land_hit(m, target, lethal, float(config.get("fire_damage", 7.0)), "gunfire" if lethal else "assault")
	if peds != null and lethal:
		peds.flee(m.global_position, 30.0, 6.0)


func _swing(m: GangMember, target: Node3D, f: Dictionary, w: Dictionary) -> void:
	m.cooldown = float(config.get("melee_rate_s", 0.9))
	if m.held != null:
		if w.is_empty():
			m.held.punch(0)
		else:
			m.held.swing()
	var lethal := bool(w.get("lethal", false)) and ContentMode.flag("lethal_weapons")
	_land_hit(m, target, lethal, float(config.get("melee_damage", 8.0)), "assault")


## A hit on the target: damage to the local player where the weapon is lethal, a tag
## otherwise; and the crime reported as the member's where an officer can see it.
func _land_hit(m: GangMember, target: Node3D, lethal: bool, damage: float, crime: String) -> void:
	if targets.size() > 0 and target == targets[0]:
		if lethal:
			hurt.emit(damage)
		else:
			tags += 1
			tagged.emit(tags)
	_report_crime(m, crime)


## Member `m`'s crime, witnessed by the police or not: never the player's stars.
func _report_crime(m: GangMember, kind: String) -> void:
	if wanted == null:
		return
	if wanted.report_other(kind, m.global_position) and police != null and bool(config.get("officers_fight_gang", true)):
		police.engage_gang(m)


## ---- hits on members ----


## True while `m` is still in the fight.
func in_fight(m: GangMember) -> bool:
	return is_instance_valid(m) and members.has(m) and m.in_fight()


## A weapon `w` hit member `m` at `pos`, fired from `from`: "stagger", "down", "tagged" or ""
## (not in the fight). A guest forwards the hit to the host. The crew goes to attack at once.
func hit_member(m: GangMember, w: Dictionary, pos: Vector3, from: Vector3) -> String:
	if mirror:
		if on_guest_hit.is_valid():
			on_guest_hit.call(m.turf_index, m.seed, str(w.get("id", "")), pos, from)
		return "sent"
	if not in_fight(m):
		return ""
	var kind := str(w.get("impact", ""))
	var key := "kick" if str(w.get("move", "")) == "kick" else kind
	var crew := _crews[m.turf_index]
	if int(crew["state"]) != Crew.FLEE and int(crew["state"]) != Crew.REGROUP:
		_set_crew(m.turf_index, Crew.ATTACK)
	if kind == "fist" and not ContentMode.flag("violence"):
		_stagger(m, from)
		return "stagger"
	if _clock - m.last_hit > float(config.get("recover_s", 3.0)):
		m.hp = m.toughness
	m.hp -= float((config.get("damage", {}) as Dictionary).get(key, config.get("default_damage", 34.0)))
	m.last_hit = _clock
	if m.hp > 0.0:
		_stagger(m, from)
		return "stagger"
	var at := m.global_position
	var result := "tagged"
	if outcome() == "tag_out":
		_tag_out(m)
	else:
		var push := pos - from
		push.y = 0.0
		push = push.normalized() * float(config.get("down_push", 350.0)) + Vector3.UP * 50.0
		_knock_down(m, push, pos)
		result = "down"
	member_down.emit(at)
	return result


## What happens to a beaten member, from the mode data (`outcomes.gang`); a tone without
## violence never knocks down.
static func outcome() -> String:
	var o := ContentMode.outcome("gang", "knock_down")
	return o if o == "tag_out" or ContentMode.flag("violence") else "tag_out"


func _stagger(m: GangMember, from: Vector3) -> void:
	var away := m.global_position - from
	away.y = 0.0
	if away.length() > 0.01:
		m.global_position += away.normalized() * float(config.get("stagger_push_m", 0.5))
	m.stagger_t = float(config.get("stagger_s", 0.5))
	_hold_pose(m, PoliceManager.stagger_pose(), {})


func _step_stagger(m: GangMember, delta: float) -> bool:
	if m.stagger_t <= 0.0:
		return false
	m.stagger_t -= delta
	if m.stagger_t <= 0.0:
		_release_pose(m)
		if m.state == GangMember.State.ALERT:
			_hold_pose(m, _hand_up_pose(), {})
	return true


func _knock_down(m: GangMember, impulse: Vector3, point: Vector3) -> void:
	_leave_fight(m, GangMember.State.DOWN)
	var rd := CharacterRagdoll.new()
	rd.name = "Ragdoll"
	m.add_child(rd)
	rd.begin(m.rig.profile, m.rig.global_transform, m.rig.phase, m.rig.amount)
	rd.apply_impulse(impulse, point, float(config.get("down_spread", 0.6)))
	m.rig.visible = false
	m.ragdoll = rd
	m.state_t = 0.0


func _tag_out(m: GangMember) -> void:
	_leave_fight(m, GangMember.State.TAGGED)
	m.rig.position.y = -float(config.get("sit_drop_m", 0.72)) * float(m.rig.profile.get("height", 1.0))
	_hold_pose(m, PoliceManager.hands_up_pose(), PoliceManager.sit_pose())
	m.state_t = 0.0


func _leave_fight(m: GangMember, state: int) -> void:
	members.erase(m)
	downed.append(m)
	m.state = state
	m.stagger_t = 0.0
	if m.body != null:
		m.body.disable()
	if m.held != null:
		m.held.set_weapon({})
		m.held.aiming = false
	# A fresh member takes their place after the respawn time.
	var f := faction(m.faction_id)
	_crews[m.turf_index]["respawns"].append({"t": float(tun(f, "respawn_s", 45.0)), "leader": m.leader})


func _step_out_of_action(m: GangMember, delta: float) -> void:
	if not is_instance_valid(m):
		downed.erase(m)
		return
	m.state_t += delta
	match m.state:
		GangMember.State.DOWN:
			if m.state_t >= float(config.get("down_settle_s", 3.0)) and m.ragdoll != null and not m.ragdoll.is_settled():
				m.ragdoll.settle()
		GangMember.State.TAGGED:
			if m.state_t >= float(config.get("tag_out_s", 8.0)):
				m.rig.position.y = 0.0
				_release_pose(m)
				m.state = GangMember.State.RETURNING
				m.state_t = 0.0
		GangMember.State.RETURNING:
			var h := home(turfs[m.turf_index])
			if m.global_position.distance_to(h) <= 3.0 or m.state_t > 30.0:
				downed.erase(m)
				m.queue_free()
			else:
				_go_to(m, h, float(config.get("patrol_speed_mps", 1.4)), delta)


func _step_respawns(delta: float) -> void:
	for i in range(turfs.size()):
		var c := _crews[i]
		var due: Array = []
		for r: Dictionary in c["respawns"]:
			r["t"] = float(r["t"]) - delta
			if float(r["t"]) <= 0.0:
				due.append(r)
		for r: Dictionary in due:
			(c["respawns"] as Array).erase(r)
			var t := turfs[i]
			var f := faction(t.faction)
			_make_member(f, i, bool(r["leader"]), home(t), _next_seed)
			_next_seed += 1
			# Whoever lay there is gone with the respawn.
			for m in downed.duplicate():
				if m.turf_index == i and m.state == GangMember.State.DOWN:
					downed.erase(m)
					m.queue_free()
					break


## ---- the faction car ----


## Full heat: the leader (or the first standing member) drives the faction car at the player
## once; it stops near them and the riders get out and attack.
func _send_car(i: int, target: Node3D) -> void:
	var c := _crews[i]
	if c["car"] != null or graph == null or graph.nodes.is_empty():
		return
	var t := turfs[i]
	var f := faction(t.faction)
	var best: RoadGraph.RoadNode = null
	var best_d := INF
	for n: RoadGraph.RoadNode in graph.nodes.values():
		var d := Vector2(n.position.x, n.position.z).distance_to(t.centre)
		if d < best_d:
			best_d = d
			best = n
	if best == null or best_d > 400.0:
		return
	var car: VehicleBody3D = CAR_SCENE.instantiate()
	var spec: Dictionary = f.get("car", {})
	car.set("vehicle_id", str(spec.get("catalogue_id", "sedan")))
	holder.add_child(car)
	var col: Array = spec.get("colour", [0.1, 0.1, 0.12])
	car.call("set_body_color", Color(float(col[0]), float(col[1]), float(col[2])))
	car.global_position = best.position + Vector3.UP * 0.6
	car.look_at(Vector3(target.global_position.x, car.global_position.y, target.global_position.z), Vector3.UP)
	car.set_meta("faction", t.faction)
	var riders: Array[GangMember] = []
	for m in _crew_members(i):
		if m.leader or riders.size() < 2:
			if riders.size() < 2:
				riders.append(m)
	for m in riders:
		m.in_car = true
		m.visible = false
		m.body.disable()
	car.set_meta("riders", riders)
	c["car"] = car
	c["car_t"] = 0.0
	_plan = {}
	car_sent.emit(car)


func _step_car(target: Node3D, delta: float) -> void:
	for i in range(turfs.size()):
		var c := _crews[i]
		var car: VehicleBody3D = c["car"]
		if car == null:
			continue
		if not is_instance_valid(car) or target == null:
			c["car"] = null
			continue
		c["car_t"] = float(c["car_t"]) + delta
		var d := car.global_position.distance_to(target.global_position)
		if car.has_meta("arrived"):
			if d > float(config.get("car_despawn_m", 220.0)):
				car.queue_free()
				c["car"] = null
			continue
		if d <= float(config.get("car_arrive_m", 9.0)) or float(c["car_t"]) > CAR_TIMEOUT_S:
			_car_arrives(i, car)
			continue
		_drive(car, target.global_position, delta)


func _drive(car: VehicleBody3D, goal: Vector3, delta: float) -> void:
	var d := car.global_position.distance_to(goal)
	var aim := goal
	if d > 35.0 and graph != null:
		var age := float(_plan.get("age", REPLAN_S)) + delta
		if age >= REPLAN_S:
			var pts := RoadRoute.find(graph, car.global_position, goal)
			var nearest := 0
			for k in range(pts.size()):
				if car.global_position.distance_to(pts[k]) < car.global_position.distance_to(pts[nearest]):
					nearest = k
			_plan = {"points": pts, "i": mini(nearest + 1, maxi(pts.size() - 1, 0)), "age": 0.0}
		else:
			_plan["age"] = age
		var pts: PackedVector3Array = _plan.get("points", PackedVector3Array())
		var k := int(_plan.get("i", 0))
		while k < pts.size() - 1 and car.global_position.distance_to(pts[k]) < 8.0:
			k += 1
		_plan["i"] = k
		if not pts.is_empty():
			aim = pts[k]
	var local := car.to_local(aim)
	var angle := atan2(-local.x, -local.z)
	car.set("override_steer", clampf(angle * STEER_GAIN, -1.0, 1.0))
	var speed := float(car.call("speed_kph"))
	var limit := 80.0 if d > 35.0 else clampf(d * 2.0, 15.0, 60.0)
	car.set("override_throttle", 1.0 if speed < limit else 0.0)
	car.set("override_hold", false)


func _car_arrives(i: int, car: VehicleBody3D) -> void:
	car.set("override_throttle", 0.0)
	car.set("override_steer", 0.0)
	car.set("override_hold", true)
	car.set_meta("arrived", true)
	var riders: Array = car.get_meta("riders", [])
	var k := 0
	for m in riders:
		if not is_instance_valid(m):
			continue
		m.in_car = false
		m.visible = true
		if m.in_fight():
			m.body.enable()
		m.global_position = car.global_position + car.global_basis.x * (2.2 if k % 2 == 0 else -2.2) + Vector3.DOWN * 0.6
		k += 1
	_set_crew(i, Crew.ATTACK)


## ---- poses ----


func _hold_pose(m: GangMember, arms: Dictionary, legs: Dictionary) -> void:
	if m.held != null:
		m.held.process_mode = Node.PROCESS_MODE_DISABLED
	m.rig.bone_override = arms
	m.rig.override_weight = 1.0 if not arms.is_empty() else 0.0
	m.rig.leg_override = legs
	m.rig.leg_weight = 1.0 if not legs.is_empty() else 0.0
	m.rig.repose()


func _release_pose(m: GangMember) -> void:
	m.rig.override_weight = 0.0
	m.rig.leg_weight = 0.0
	m.rig.repose()
	if m.held != null:
		m.held.process_mode = Node.PROCESS_MODE_INHERIT


## The warning: one arm up, palm out.
static func _hand_up_pose() -> Dictionary:
	return {
		"upper_arm_r": Quaternion(Vector3.RIGHT, 2.6),
		"forearm_r": Quaternion(Vector3.RIGHT, 0.3),
	}


## ---- co-op ----


## Members near `around` as floats: turf, faction, seed, leader, x, y, z, yaw, state, in_car.
func snapshot(around: Vector3, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for m in members + downed:
		if not is_instance_valid(m) or m.global_position.distance_to(around) > radius:
			continue
		var fwd := -m.global_basis.z
		out.append_array(PackedFloat32Array([float(m.turf_index), float(m.faction_index), float(m.seed), 1.0 if m.leader else 0.0, m.global_position.x, m.global_position.y, m.global_position.z, atan2(fwd.x, fwd.z), float(m.state), 1.0 if m.in_car else 0.0]))
	return out


## Guest: builds or moves replicas from the host's snapshot and poses them by state.
func apply_snapshot(data: PackedFloat32Array) -> void:
	var seen := {}
	var k := 0
	while k + SNAPSHOT_STRIDE <= data.size():
		var turf_i := int(data[k])
		var seed := int(data[k + 2])
		seen[seed] = true
		var m := _replica(seed)
		if m == null:
			var f := factions[clampi(int(data[k + 1]), 0, maxi(factions.size() - 1, 0))] if not factions.is_empty() else {}
			if f.is_empty() or turf_i >= turfs.size():
				k += SNAPSHOT_STRIDE
				continue
			m = _make_member(f, turf_i, data[k + 3] > 0.5, Vector3(data[k + 4], data[k + 5], data[k + 6]), seed)
		var pos := Vector3(data[k + 4], data[k + 5], data[k + 6])
		var moved := pos.distance_to(m.global_position)
		m.global_position = pos
		var yaw := data[k + 7]
		m.global_basis = Basis(Vector3.UP, yaw + PI)
		var state := int(data[k + 8])
		if state != m.state:
			m.state = state
			if state == GangMember.State.TAGGED:
				_hold_pose(m, PoliceManager.hands_up_pose(), PoliceManager.sit_pose())
			elif state == GangMember.State.ALERT:
				_hold_pose(m, _hand_up_pose(), {})
			else:
				_release_pose(m)
			m.rig.visible = state != GangMember.State.DOWN
		m.in_car = data[k + 9] > 0.5
		m.visible = not m.in_car
		m.rig.advance(1.0 / 15.0, moved * 15.0)
		k += SNAPSHOT_STRIDE
	for m in members.duplicate():
		if not seen.has(m.seed):
			members.erase(m)
			m.queue_free()


func _replica(seed: int) -> GangMember:
	for m in members:
		if m.seed == seed:
			return m
	return null


## The member with `seed` (the host, on a guest's hit report).
func member_by_seed(seed: int) -> GangMember:
	return _replica(seed)


## A ground height at `p`: a ray down on the world layer, else `fallback`.
func _ground_y(p: Vector3, fallback: float) -> float:
	if holder == null or not holder.is_inside_tree():
		return fallback
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 60.0, p + Vector3.DOWN * 60.0, 1)
	var res := holder.get_world_3d().direct_space_state.intersect_ray(q)
	return float((res["position"] as Vector3).y) if not res.is_empty() else fallback


## Everything off the ground (a new pack, tests).
func reset() -> void:
	for m in members + downed:
		if is_instance_valid(m):
			m.queue_free()
	members = []
	downed = []
	for c in _crews:
		if c["car"] != null and is_instance_valid(c["car"]):
			(c["car"] as Node).queue_free()
	_crews = []
	turfs = []
	tags = 0
