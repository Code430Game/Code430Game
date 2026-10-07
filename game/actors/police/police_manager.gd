class_name PoliceManager
extends Node3D
## The police response (add-police 2.2-2.4). With a wanted level it keeps `police_per_star`
## patrol cars chasing the player: they spawn out of view on a road node `spawn_min_m` to
## `spawn_max_m` away, follow a road-graph path toward the player (re-planned every couple of
## seconds) and drive straight at them once close, light bars flashing and a siren wailing.
## A stopped car near a player on foot, or near the player's own stopped car, lets an officer
## out who runs at them (or to the driver's door) and, at a player on foot, uses the officer
## weapon the tone gives (a net that holds the player in `clean`, a pistol or blaster at the
## top level elsewhere), or fists at arm's length when the tone allows no officer weapon
## (add-unarmed-combat). Held still with an officer beside them for `busted_s`, the player is
## busted. Officers left far behind are dropped; cars and officers leave when the level clears.
## A patrol car whose officer is out stays parked; when the player drives off, the officer
## runs back and gets in, and an officer left far behind takes the empty car with them
## (update-police-pursuit). Each unit sees the player within `police_sight_m`, which the
## minimap shows (`markers`).
##
## Fighting back (add-police-combat): each officer carries an `OfficerBody` the player's weapons
## reach, and `hit_officer` takes it from there. A hit costs the officer toughness by the
## weapon's impact (`officer_combat.damage`), which comes back after `recover_s` without hits;
## until it runs out they stagger and then take cover by their car. Spent, they go out of the
## fight the way the tone's mode data says (`outcomes.officer`): knocked down as a ragdoll, or
## tagged out (sitting, hands up, then walking back to the car). Fists follow the unarmed
## rules: no violence, no harm, only a stagger. Hitting an officer is `assault_officer`, always
## seen; one out of the fight is `officer_down`, and backup drives to where it happened.

signal busted
signal net_hit(seconds: float)
## The player on foot was shot or punched by an officer.
signal shot_at(damage: float)
## Someone got in and took a patrol car (#69): it is theirs now.
signal taken(car: VehicleBody3D)
## An officer went out of the fight at `at` (knocked down or tagged out).
signal officer_down(at: Vector3)
## Someone got into the police helicopter parked on its pad (add-flyable-helicopter).
signal aircraft_taken(heli: FlyableHelicopter)

const CAR_SCENE := preload("res://actors/vehicles/placeholder_car.tscn")
const REPLAN_S := 2.0
const DIRECT_M := 35.0
const STEER_GAIN := 1.6
const STUCK_S := 3.0
const HELI_FAR_PAD_M := 700.0
const HELI_ARRIVE_M := 400.0

var wanted: Wanted
var graph: RoadGraph
var player: Player
var holder: Node3D  # where cars and officers live (the world)
var stations: Array = []  # Services.Place of kind police: the first car leaves from one in range
var helipads: Array = []  # Services.Place of kind helipad: where the helicopter lives
var helicopter: PoliceHelicopter
## The police helicopter standing on its pad while it isn't flying (add-flyable-helicopter):
## the AI helicopter lifts off in its place and parks it again when it lands. Null while it is
## up, or taken.
var parked_helicopter: FlyableHelicopter
## The helicopter a player took from the pad: no police air unit until a new one is back at
## the pad (`air_return_s` after the theft, and not while a player still flies the old one).
var stolen_helicopter: FlyableHelicopter
## The guest flying the stolen helicopter (co-op host only). The host frees its replica of a
## guest's helicopter, so this is what keeps the air unit grounded until that guest leaves.
var guest_pilot_peer: int = 0
var _air_back_s: float = 0.0
var _pad_marker: Node3D
## The map's extent on x and z, for the flyable helicopter's soft boundary.
var air_bounds: Rect2 = Rect2()
## Dense canopy that hides the player from the helicopter (set by the scene; null: none).
var canopy: CanopyCover
## 0 day .. 1 night (the scene's day-night clock), for the helicopter's searchlight.
var night: float = 0.0
var _rotor_voice: AudioStreamPlayer
var _rotor_phase: float = 0.0  # AI helicopter rotor beat phase, wrapped at TAU
var _noise_state: Array = [0x1234567]
var cars: Array[VehicleBody3D] = []
var officers: Array[Node3D] = []
## Officers out of the fight (down, or tagged out and walking back): they neither move on the
## player nor see them, and stay until the chase ends.
var downed: Array[Node3D] = []
var _clock: float = 0.0
var _plans: Dictionary = {}  # car -> {"points": PackedVector3Array, "i": int, "age": float}
var _flash: float = 0.0
var _busted_s: float = 0.0
var _officer_cooldown: Dictionary = {}
var _siren: AudioStreamPlayer
var _siren_phase: float = 0.0
var _siren_on: bool = false
var _rng := RandomNumberGenerator.new()
var _officer_weapon: Dictionary = {}
## Prints the chase each second (the testbed's --police-log).
var log_chase: bool = false
var _log_s: float = 0.0


func _ready() -> void:
	_rng.seed = 430
	_siren = Synth.make_player("SFX", -12.0)
	add_child(_siren)
	_siren.play()
	_rotor_voice = Synth.make_player("SFX", -8.0)
	add_child(_rotor_voice)
	_rotor_voice.play()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://actors/police/officer_weapon.json"))
	_officer_weapon = data if data is Dictionary else {}


func cfg(key: String, fallback: Variant) -> Variant:
	return wanted.config.get(key, fallback) if wanted != null else fallback


func _target() -> Node3D:
	if player == null:
		return null
	return player.vehicle if player.is_driving() and player.vehicle != null else player


func _physics_process(delta: float) -> void:
	if wanted == null or player == null or get_tree().paused:
		return
	_clock += delta
	_step_parked_helicopter(delta)
	var target := _target()
	var want: int = (cfg("police_per_star", [0, 1, 2, 4]) as Array)[clampi(wanted.stars, 0, 3)]
	want = mini(want, int(cfg("max_police", 4)))
	if wanted.stars == 0:
		_clear_all()
	else:
		while cars.size() < want:
			if not _spawn_car(target.global_position):
				break
	var positions := PackedVector3Array()
	for car in cars.duplicate():
		if not is_instance_valid(car):
			cars.erase(car)
			continue
		if int(car.get("driver_peer_id")) != 0:
			hand_over(car)
			continue
		if car.global_position.distance_to(target.global_position) > float(cfg("despawn_m", 260.0)):
			_remove_car(car)
			continue
		_drive(car, target, delta)
		_unstick(car, target, delta)
		positions.append(car.global_position)
	for o in officers.duplicate():
		if not is_instance_valid(o):
			officers.erase(o)
			continue
		if o.global_position.distance_to(target.global_position) > float(cfg("officer_lost_m", 90.0)):
			_drop_officer(o)  # left far behind (the player drove off): their empty car goes too
			continue
		if _officer_boards(o, delta):
			continue
		_step_officer(o, delta)
		positions.append(o.global_position)
	for o in downed.duplicate():
		_step_out_of_action(o, delta)
	_step_helicopter(target)
	wanted.police_positions = positions
	_maybe_let_out(target)
	_check_busted(delta)
	_flash += delta
	if log_chase:
		_log_s += delta
		if _log_s >= 1.0:
			_log_s = 0.0
			var line := "police: stars %d cars %d officers %d" % [wanted.stars, cars.size(), officers.size()]
			for car in cars:
				line += " | d %.0f y %.1f v %.0f" % [car.global_position.distance_to(target.global_position), car.global_position.y, float(car.call("speed_kph"))]
			if helicopter != null:
				line += " | heli %s d %.0f alt %.0f sees %s" % [PoliceHelicopter.State.keys()[helicopter.state], helicopter.global_position.distance_to(target.global_position), helicopter.global_position.y - target.global_position.y, helicopter.sees_target()]
			print(line)


## A player took patrol car `car`: no more steering it, never freed with the thief inside, and
## its light bar goes dark (as an ambulance's does); it is an ordinary car now.
func hand_over(car: VehicleBody3D) -> void:
	cars.erase(car)
	_plans.erase(car)
	car.remove_meta("police")
	var bar: Node3D = car.get_node_or_null("LightBar")
	if bar != null:
		bar.visible = false
	taken.emit(car)


func _process(_delta: float) -> void:
	# Light bars alternate red and blue at about 3 Hz.
	var on := fmod(_flash * 3.0, 1.0) < 0.5
	for car in cars:
		if is_instance_valid(car):
			var bar: Node3D = car.get_node_or_null("LightBar")
			if bar != null:
				(bar.get_child(0) as MeshInstance3D).visible = on
				(bar.get_child(1) as MeshInstance3D).visible = not on
	_fill_siren()
	_fill_rotor()


func _spawn_car(around: Vector3, backup_to: Vector3 = Vector3.INF) -> bool:
	if graph == null or graph.nodes.is_empty():
		return false
	var lo := float(cfg("spawn_min_m", 90.0))
	var hi := float(cfg("spawn_max_m", 160.0))
	var cam := get_viewport().get_camera_3d()
	var best: RoadGraph.RoadNode = null
	if cars.is_empty():
		for st in stations:
			var node: RoadGraph.RoadNode = graph.nodes.get(st.road_node)
			if node != null and node.position.distance_to(around) <= hi * 1.5 and not route(node.position, around).is_empty():
				best = node  # the first car of a chase rolls out of the station
				break
	var ids := graph.nodes.keys()
	for k in range(0 if best != null else 60):
		var n: RoadGraph.RoadNode = graph.nodes[ids[_rng.randi_range(0, ids.size() - 1)]]
		var d := n.position.distance_to(around)
		if d < lo or d > hi or absf(n.position.y - around.y) > 5.0:
			continue
		if cam != null and cam.is_position_in_frustum(n.position) and d < hi:
			continue  # out of view, not popping in
		if route(n.position, around).is_empty():
			continue  # on a piece of road that does not reach the player
		best = n
		break
	if best == null:
		return false
	var car: VehicleBody3D = CAR_SCENE.instantiate()
	car.set("vehicle_id", "police")
	holder.add_child(car)
	car.call("set_body_color", Color(0.95, 0.95, 0.97))  # the catalogue's white, not the default red
	car.global_position = best.position + Vector3.UP * 0.6
	car.set("radio_station", Radio.pick_for_car(hash(best.position.snapped(Vector3.ONE)), true))
	# Facing along the road it will take, not straight at the player (through whatever is between).
	var path := route(best.position, around)
	var ahead := around
	for q in path:
		if Vector2(q.x - best.position.x, q.z - best.position.z).length() > 1.0:
			ahead = q
			break
	car.look_at(Vector3(ahead.x, car.global_position.y, ahead.z), Vector3.UP)
	if car.has_method("add_headlights"):
		car.add_headlights(false)
		car.set_headlights(1.0)
	car.add_child(_light_bar(car))
	car.set_meta("police", true)
	if backup_to != Vector3.INF:
		car.set_meta("backup_to", backup_to)
	cars.append(car)
	return true


func _light_bar(car: VehicleBody3D) -> Node3D:
	var bar := Node3D.new()
	bar.name = "LightBar"
	var h := float(car.get("height")) if car.get("height") != null else 1.45
	for side: float in [-1.0, 1.0]:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 0.12, 0.2)
		m.mesh = box
		var mat := StandardMaterial3D.new()
		var c := Color(1.0, 0.1, 0.1) if side < 0.0 else Color(0.15, 0.35, 1.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = c
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 4.0
		m.material_override = mat
		m.position = Vector3(side * 0.25, h + 0.08, 0.0)
		var glow := OmniLight3D.new()
		glow.light_color = c
		glow.light_energy = 1.5
		glow.omni_range = 7.0
		m.add_child(glow)
		bar.add_child(m)
	return bar


func _drive(car: VehicleBody3D, target: Node3D, delta: float) -> void:
	if car.has_meta("officer_out"):
		# Nobody at the wheel: parked, handbrake on, until the officer is back.
		car.set("override_throttle", 0.0)
		car.set("override_steer", 0.0)
		car.set("override_hold", true)
		return
	var goal := target.global_position
	if car.has_meta("backup_to"):
		# Backup heads for where an officer went down; once there it lets its officer out.
		goal = car.get_meta("backup_to")
		if car.global_position.distance_to(goal) <= float(combat("backup_arrive_m", 15.0)):
			car.remove_meta("backup_to")
			car.set_meta("ready_out", true)
			goal = target.global_position
	var d := car.global_position.distance_to(goal)
	var aim := goal
	if d > DIRECT_M:
		var plan: Dictionary = _plans.get(car, {})
		var age := float(plan.get("age", REPLAN_S)) + delta
		if age >= REPLAN_S:
			var pts_new := route(car.global_position, goal)
			# The route ends at the goal itself; from the last node that is a straight line that can
			# run into a pier or a wall (a player under a deck). End on the road nearest the goal.
			var on_road := _road_point(goal)
			if pts_new.size() > 1 and on_road != Vector3.INF:
				pts_new[pts_new.size() - 1] = on_road
			# Start past the route point nearest the car, or it turns back to it every re-plan.
			var nearest := 0
			for k in range(pts_new.size()):
				if car.global_position.distance_to(pts_new[k]) < car.global_position.distance_to(pts_new[nearest]):
					nearest = k
			plan = {"points": pts_new, "i": mini(nearest + 1, maxi(pts_new.size() - 1, 0)), "age": 0.0}
		else:
			plan["age"] = age
		var pts: PackedVector3Array = plan["points"]
		var i := int(plan["i"])
		while i < pts.size() - 1 and car.global_position.distance_to(pts[i]) < 8.0:
			i += 1
		plan["i"] = i
		_plans[car] = plan
		if not pts.is_empty():
			aim = pts[i]
	var local := car.to_local(aim)
	var angle := atan2(-local.x, -local.z)
	car.set("override_steer", clampf(angle * STEER_GAIN, -1.0, 1.0))
	var speed := float(car.call("speed_kph"))
	var limit := 95.0 if d > DIRECT_M else clampf(d * 2.0, 15.0, 70.0)
	if wanted.stars >= 2 and d < DIRECT_M:
		limit = 70.0  # ram and box in
	var stopped_car := player.is_driving() and absf(float(target.call("speed_kph"))) <= float(cfg("officer_car_stopped_kph", 8.0))
	if d < float(cfg("pull_up_m", 7.0)) and (not player.is_driving() or stopped_car):
		car.set("override_throttle", 0.0)
		car.set("override_hold", true)  # pull up beside a player on foot or a stopped car (brake alone would reverse)
	else:
		car.set("override_throttle", 1.0 if speed < limit else 0.0)


## Road-graph route from `from` to `to` (see RoadRoute.find).
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	return RoadRoute.find(graph, from, to)


## The point on the road nearest `p` at about its height (a player under a deck is reached
## from the road below), or Vector3.INF when no road is near.
func _road_point(p: Vector3) -> Vector3:
	if graph == null:
		return Vector3.INF
	var hit := graph.nearest_edge(p, 80.0, RoadRoute.SAME_LEVEL_M)
	return hit["point"] if not hit.is_empty() else Vector3.INF


## A car that has barely moved for a while is blocked: a pier, a wall, a kerb it can't climb.
## Close enough for the officer to go on foot (the player on foot or stopped, within
## `officer_out_blocked_m`), the officer gets out after `blocked_s` and the car stays put; farther
## off, after STUCK_S, it is taken away and sent in again from a fresh spot. A car parked on
## purpose (its officer out or about to be, or pulled up beside the player) is never moved.
func _unstick(car: VehicleBody3D, target: Node3D, delta: float) -> void:
	var d := car.global_position.distance_to(target.global_position)
	var parked := car.has_meta("officer_out") or car.has_meta("ready_out") or d < float(cfg("pull_up_m", 7.0))
	if parked or absf(float(car.call("speed_kph"))) >= 3.0:
		car.set_meta("stuck_s", 0.0)
		return
	var t := float(car.get_meta("stuck_s", 0.0)) + delta
	car.set_meta("stuck_s", t)
	var player_still := not player.is_driving() or absf(float(target.call("speed_kph"))) <= float(cfg("officer_car_stopped_kph", 8.0))
	if player_still and d <= float(cfg("officer_out_blocked_m", 70.0)) and t >= float(cfg("blocked_s", 1.5)):
		car.set_meta("ready_out", true)  # can't get closer: the officer goes on foot from here
		car.set_meta("stuck_s", 0.0)
		return
	if d > DIRECT_M and t >= STUCK_S:
		_remove_car(car)


func _maybe_let_out(target: Node3D) -> void:
	for car in cars:
		if car.has_meta("ready_out") and not car.has_meta("officer_out") and absf(float(car.call("speed_kph"))) < 6.0:
			car.remove_meta("ready_out")  # backup at the scene: out at once
			car.set_meta("officer_out", true)
			var ready := _make_officer(car.global_position + car.global_basis.x * 1.6)
			ready.set_meta("car", car)
			officers.append(ready)
			return
	if officers.size() >= cars.size():
		return
	if player.is_driving() and absf(float(target.call("speed_kph"))) > float(cfg("officer_car_stopped_kph", 8.0)):
		return  # a car still moving: they stay in and chase
	for car in cars:
		if car.has_meta("officer_out"):
			continue
		if car.global_position.distance_to(target.global_position) < float(cfg("officer_get_out_m", 25.0)) and absf(float(car.call("speed_kph"))) < 6.0:
			car.set_meta("officer_out", true)
			var o := _make_officer(car.global_position + car.global_basis.x * 1.6)
			o.set_meta("car", car)
			officers.append(o)
			return


## The officer's patrol car, or null when it is gone or someone took it (`hand_over`).
func _car_of(o: Node3D) -> VehicleBody3D:
	if not o.has_meta("car"):
		return null
	var car: Variant = o.get_meta("car")
	if not is_instance_valid(car) or not car is VehicleBody3D:
		return null
	return car if (car as VehicleBody3D).has_meta("police") else null


## The player drove off: the officer runs back to their car and, at its door, gets in (the
## officer goes and the car drives again). Returns true while heading back or once aboard.
func _officer_boards(o: Node3D, delta: float) -> bool:
	var car := _car_of(o)
	if car == null or not player.is_driving():
		return false
	if absf(float(_target().call("speed_kph"))) <= float(cfg("officer_car_stopped_kph", 8.0)):
		return false  # still stopped: keep going for the driver's door
	var to := car.global_position - o.global_position
	to.y = 0.0
	if to.length() <= float(cfg("officer_board_m", 2.5)):
		officers.erase(o)
		_officer_cooldown.erase(o)
		o.queue_free()
		car.remove_meta("officer_out")
		return true
	var speed := float(cfg("officer_speed_mps", 4.2))
	o.global_position += to.normalized() * minf(speed * delta, to.length())
	o.look_at(Vector3(car.global_position.x, o.global_position.y, car.global_position.z), Vector3.UP)
	(o.get_meta("rig") as CharacterRig).advance(delta, speed)
	return true


## An officer left far behind: gone, and their empty car with them.
func _drop_officer(o: Node3D) -> void:
	var car := _car_of(o)
	officers.erase(o)
	_officer_cooldown.erase(o)
	o.queue_free()
	if car != null and car.has_meta("officer_out"):
		_remove_car(car)


func _make_officer(at: Vector3) -> Node3D:
	var o := Node3D.new()
	o.name = "Officer"
	var rig := CharacterRig.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = officers.size() + 7
	var p := CharacterProfile.random(rng)
	p["top"] = 1  # blue
	p["bottom"] = 5  # black
	p["jacket"] = 1
	p["jacket_colour"] = 5
	p["hat"] = 1  # cap
	rig.profile = p
	o.add_child(rig)
	o.set_meta("rig", rig)
	holder.add_child(o)
	o.global_position = at
	var held := HeldWeapon.new()  # the tone's officer weapon in hand (add-weapons-and-combat 2.6)
	held.name = "HeldWeapon"
	held.rig = rig
	o.add_child(held)
	held.set_weapon(WeaponSet.resolve(_officer_weapon))
	o.set_meta("held", held)
	var body := OfficerBody.new(float(combat("body_radius_m", 0.32)), float(combat("body_height_m", 1.8)))
	body.officer = o
	o.add_child(body)
	o.set_meta("body", body)
	return o


func _step_officer(o: Node3D, delta: float) -> void:
	var target := _target()
	if _step_stagger(o, delta):
		return
	var goal := target.global_position
	var to := goal - o.global_position
	to.y = 0.0
	var d := to.length()
	var speed := 0.0
	# Up to a player on foot, or to the driver's door of a stopped car; a hit officer goes to
	# cover behind their car first.
	var stop := float(cfg("busted_m", 3.0)) * 0.6 if not player.is_driving() else float(cfg("officer_at_car_m", 2.4))
	var move_to := goal
	var cover := cover_point(o)
	if cover != Vector3.INF:
		move_to = cover
		stop = 0.4
	var step := move_to - o.global_position
	step.y = 0.0
	if step.length() > stop:
		speed = float(cfg("officer_speed_mps", 4.2))
		o.global_position += step.normalized() * minf(speed * delta, step.length())
	if not (target is FlyableHelicopter):  # an aircraft on a roof or hovering: they stay on the ground
		o.global_position.y = lerpf(o.global_position.y, target.global_position.y, clampf(delta * 6.0, 0.0, 1.0))
	if d > 0.1:
		o.look_at(Vector3(goal.x, o.global_position.y, goal.z), Vector3.UP)  # bodies face -Z, toward the player
	(o.get_meta("rig") as CharacterRig).advance(delta, speed)
	# The tone's officer weapon.
	var cool := float(_officer_cooldown.get(o, 0.0)) - delta
	_officer_cooldown[o] = cool
	var w := WeaponSet.resolve(_officer_weapon)
	if w.is_empty():
		_officer_fists(o, d, cool)
		return
	var lethal := bool(w.get("lethal", false))
	var may_fire := not w.is_empty() and not player.is_driving() and not (lethal and wanted.stars < int(cfg("fire_min_stars", 3)))
	var held: HeldWeapon = o.get_meta("held", null)
	if held != null:
		held.aiming = may_fire and d <= float(cfg("officer_fire_m", 22.0))  # raised while in range
	if cool > 0.0 or not may_fire:
		return
	if d <= float(cfg("officer_fire_m", 22.0)):
		if held != null:
			held.recoil()
		_officer_cooldown[o] = float(cfg("officer_rate_s", 1.1)) * (3.0 if not lethal else 1.0)
		if lethal:
			shot_at.emit(float(cfg("officer_damage", 9.0)))
		else:
			net_hit.emit(float(cfg("net_s", 3.0)))


## No tone weapon for officers: a jab at a player on foot within reach, hands alternating.
func _officer_fists(o: Node3D, d: float, cool: float) -> void:
	if cool > 0.0 or player.is_driving() or d > float(cfg("officer_punch_m", 2.0)):
		return
	var held: HeldWeapon = o.get_meta("held", null)
	if held != null:
		var side := int(o.get_meta("jab", 0))
		held.punch(side)
		o.set_meta("jab", 1 - side)
	_officer_cooldown[o] = float(cfg("officer_punch_rate_s", 0.8))
	shot_at.emit(float(cfg("officer_punch_damage", 5.0)))


func _check_busted(delta: float) -> void:
	var near := false
	var target := _target()
	var at_car_m := float(cfg("officer_at_car_m", 2.4)) + 1.0
	for o in officers:
		if not is_instance_valid(o):
			continue
		if not player.is_driving() and o.global_position.distance_to(player.global_position) <= float(cfg("busted_m", 3.0)):
			near = true
		if player.is_driving() and o.global_position.distance_to(target.global_position) <= at_car_m:
			near = near or absf(float(target.call("speed_kph"))) < float(cfg("busted_speed_kph", 2.0))  # at the door
	if player.is_driving():
		for car in cars:
			if is_instance_valid(car) and car.global_position.distance_to(target.global_position) < 6.0:
				near = near or absf(float(target.call("speed_kph"))) < float(cfg("busted_speed_kph", 2.0))
	var still: bool = player.is_driving() or player.velocity.length() < 0.5 or player.stuck_s > 0.0
	if near and still:
		_busted_s += delta
		if _busted_s >= float(cfg("busted_s", 2.0)):
			_busted_s = 0.0
			busted.emit()
	else:
		_busted_s = 0.0


## The helicopter on its pad (add-flyable-helicopter): parked at the first helipad. A guest's
## copy is taken through the host (`take_by_request`).
func park_helicopter() -> FlyableHelicopter:
	if helipads.is_empty() or holder == null or parked_helicopter != null:
		return parked_helicopter
	var pad: Services.Place = helipads[0]
	if _pad_marker == null:
		_pad_marker = pad_marker()
		holder.add_child(_pad_marker)
		_pad_marker.global_position = pad.at + Vector3.UP * 0.03
	var heli := FlyableHelicopter.new()
	heli.name = "ParkedHelicopter"
	heli.bounds = air_bounds
	heli.take_by_request = Session.is_client()
	heli.radio_station = Radio.pick_for_car(hash(pad.id), true)
	holder.add_child(heli)
	heli.place_at(Transform3D(Basis(), pad.at + Vector3.UP * 0.05))
	parked_helicopter = heli
	return heli


## A helipad's markings: a concrete disc with a white ring and an H, flat on the ground.
static func pad_marker() -> Node3D:
	var root := Node3D.new()
	root.name = "HelipadMarking"
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.5
	cyl.bottom_radius = 7.5
	cyl.height = 0.06
	cyl.radial_segments = 32
	disc.mesh = cyl
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.55, 0.55, 0.53)
	concrete.roughness = 0.9
	disc.material_override = concrete
	root.add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 5.9
	torus.outer_radius = 6.3
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.05, 1.0)
	ring.position.y = 0.04
	ring.material_override = _paint()
	root.add_child(ring)
	for spec: Array in [[Vector3(-1.6, 0.04, 0), Vector3(0.7, 0.04, 5.0)], [Vector3(1.6, 0.04, 0), Vector3(0.7, 0.04, 5.0)], [Vector3(0, 0.04, 0), Vector3(2.5, 0.04, 0.7)]]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[1]
		bar.mesh = box
		bar.position = spec[0]
		bar.material_override = _paint()
		root.add_child(bar)
	return root


static func _paint() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.95, 0.92)
	m.roughness = 0.8
	return m


## Whether the police have an air unit to send: one on its pad, or (with no helipad in the
## pack) the one that comes in from the district edge.
func air_unit_available() -> bool:
	return helipads.is_empty() or parked_helicopter != null


## Watches the parked helicopter: when someone gets in it is theirs (`aircraft_taken`), and a
## new one is back at the pad `air_return_s` later, once no player still flies the old one.
func _step_parked_helicopter(delta: float) -> void:
	if parked_helicopter != null and not is_instance_valid(parked_helicopter):
		parked_helicopter = null
	if parked_helicopter != null and parked_helicopter.driver_peer_id != 0:
		take_parked_helicopter()
		aircraft_taken.emit(stolen_helicopter)
	if parked_helicopter != null and parked_helicopter.settled and _pad_marker != null:
		_pad_marker.global_position.y = parked_helicopter.global_position.y + 0.03  # on the ground it found
	if _air_back_s > 0.0:
		_air_back_s -= delta
	var flown := guest_pilot_peer != 0 or (stolen_helicopter != null and is_instance_valid(stolen_helicopter) and stolen_helicopter.driver_peer_id != 0)
	if stolen_helicopter != null and _air_back_s <= 0.0 and not flown:
		stolen_helicopter = null
	if not flown and stolen_helicopter == null and parked_helicopter == null and helicopter == null and _air_back_s <= 0.0:
		park_helicopter()


## The parked helicopter is taken (by the local player getting in, or by a guest through the
## host): no longer the police's, and their air unit is gone until a new one is back.
func take_parked_helicopter() -> FlyableHelicopter:
	if parked_helicopter == null:
		return null
	stolen_helicopter = parked_helicopter
	parked_helicopter = null
	stolen_helicopter.name = "StolenHelicopter"
	_air_back_s = float(cfg("air_return_s", 240.0))
	return stolen_helicopter


## A guest's grant from the host (add-flyable-helicopter): their own helicopter at `t`, stolen.
func fly_granted_helicopter(t: Transform3D) -> FlyableHelicopter:
	var heli := FlyableHelicopter.new()
	heli.name = "StolenHelicopter"
	heli.bounds = air_bounds
	holder.add_child(heli)
	heli.place_at(t)
	stolen_helicopter = heli
	_air_back_s = float(cfg("air_return_s", 240.0))
	return heli


## A helicopter left at `t` by a pilot who is gone (a guest leaving mid-flight): it lands
## itself where it is and parks; anyone may take it. Not the police's.
func leave_helicopter(t: Transform3D) -> FlyableHelicopter:
	guest_pilot_peer = 0
	var heli := FlyableHelicopter.new()
	heli.name = "LeftHelicopter"
	heli.bounds = air_bounds
	holder.add_child(heli)
	heli.global_transform = t
	heli.heading = t.basis.get_euler().y
	return heli


## Three stars bring the helicopter from the nearest helipad (or high at the district edge);
## below three it goes home and parks again when it lands. With its pad empty (the player took
## it) there is no air unit.
func _step_helicopter(target: Node3D) -> void:
	if wanted.stars >= 3 and helicopter == null and air_unit_available():
		if parked_helicopter != null:
			parked_helicopter.queue_free()  # it lifts off as the AI helicopter
			parked_helicopter = null
		helicopter = PoliceHelicopter.new()
		helicopter.name = "PoliceHelicopter"
		helicopter.config = cfg("helicopter", {})
		helicopter.canopy = canopy
		var pad: Variant = null
		for h in helipads:
			if pad == null or h.at.distance_to(target.global_position) < pad.at.distance_to(target.global_position):
				pad = h
		var home: Vector3 = pad.at if pad != null else target.global_position + Vector3(260.0, 0.0, 0.0)
		holder.add_child(helicopter)
		helicopter.home = home
		helicopter.last_seen = target.global_position  # where the call came from
		if pad != null and home.distance_to(target.global_position) <= HELI_FAR_PAD_M:
			helicopter.global_position = home  # lifts off from the pad
		else:
			# A far pad: it is already on its way, coming in from the pad's side at cruise height.
			var from := home - target.global_position
			from.y = 0.0
			from = from.normalized() * HELI_ARRIVE_M if from.length() > 1.0 else Vector3(HELI_ARRIVE_M, 0.0, 0.0)
			helicopter.global_position = target.global_position + from + Vector3.UP * helicopter.tun("cruise_m")
			helicopter.state = PoliceHelicopter.State.CHASE
		helicopter.landed.connect(_on_helicopter_landed)
	if helicopter == null:
		wanted.helicopter_sees = false
		return
	helicopter.target = target
	helicopter.night = night
	if wanted.police_sees(target.global_position):
		helicopter.tip(target.global_position)  # a car or officer has them: search there
	if wanted.stars < 3:
		helicopter.go_home()
		if helicopter.global_position.distance_to(target.global_position) > HELI_FAR_PAD_M:
			_on_helicopter_landed()  # well out of sight on its way home
			return
	wanted.helicopter_sees = helicopter.sees_target()


## A tunable from `officer_combat` in the police config.
func combat(key: String, fallback: Variant) -> Variant:
	return (cfg("officer_combat", {}) as Dictionary).get(key, fallback)


## What happens to an officer whose toughness runs out, from the mode data
## (`outcomes.officer`): "knock_down" or "tag_out". A tone without violence never knocks down.
static func outcome() -> String:
	var o := ContentMode.outcome("officer", "knock_down")
	return o if o == "tag_out" or ContentMode.flag("violence") else "tag_out"


## Puts an officer on foot at `at` (tests, the testbed's --officer).
func place_officer(at: Vector3) -> Node3D:
	var o := _make_officer(at)
	officers.append(o)
	return o


## Screenshots (the testbed's --officer): an officer 5 m in front of the camera, facing it, hit
## with the tone's gun into `state` ("stagger" held, "down" or "tagged").
func demo_officer(state: String, by: Node3D) -> void:
	if wanted != null and wanted.stars == 0:
		wanted.set_stars(1)
	var cam: Camera3D = (by as Player).camera() if by is Player else get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z if cam != null else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized()
	# Ahead and a little to the side, so the player's own body doesn't hide them.
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var o := place_officer(by.global_position + fwd * 5.0 + side * 1.6)
	o.look_at(Vector3(by.global_position.x, o.global_position.y, by.global_position.z), Vector3.UP)
	print("police: demo officer %s at %s (player at %s)" % [state, o.global_position, by.global_position])
	var ws := WeaponSet.new()
	ws.slot = 2
	var w := ws.current()
	var from := by.global_position + Vector3.UP
	var tries := 0
	while in_fight(o) and tries < 10:
		var r := hit_officer(o, w, o.global_position + Vector3.UP, from)
		tries += 1
		if state == "stagger" and r == "stagger":
			o.set_meta("stagger_t", 3600.0)  # held for the picture
			return


## True while `o` is an officer still in the fight (not down, not tagged out).
func in_fight(o: Node3D) -> bool:
	return officers.has(o)


## The player's weapon `w` hit officer `o` at `pos`, fired from `from`. Always counts as
## `assault_officer`; returns what happened: "stagger", "down", "tagged" or "" (not in the fight).
func hit_officer(o: Node3D, w: Dictionary, pos: Vector3, from: Vector3) -> String:
	if not in_fight(o):
		return ""
	if wanted != null:
		wanted.report("assault_officer", o.global_position, true)
	var kind := str(w.get("impact", ""))
	var key := "kick" if str(w.get("move", "")) == "kick" else kind
	if kind == "fist" and not ContentMode.flag("violence"):
		_stagger(o, from)  # a shove: fists never harm where the tone has no violence
		return "stagger"
	var toughness := float(combat("toughness", 100.0))
	var hp := float(o.get_meta("hp", toughness))
	if _clock - float(o.get_meta("last_hit", -INF)) > float(combat("recover_s", 3.0)):
		hp = toughness
	hp -= float((combat("damage", {}) as Dictionary).get(key, combat("default_damage", 34.0)))
	o.set_meta("hp", hp)
	o.set_meta("last_hit", _clock)
	if hp > 0.0:
		_stagger(o, from)
		return "stagger"
	var at := o.global_position
	var result := "tagged"
	if outcome() == "tag_out":
		_tag_out(o)
	else:
		var push := pos - from
		push.y = 0.0
		push = push.normalized() * float(combat("down_push", 350.0)) + Vector3.UP * 50.0
		_knock_down(o, push, pos)
		result = "down"
	if wanted != null:
		wanted.report("officer_down", at, true)
	_call_backup(at)
	officer_down.emit(at)
	return result


## A hit that doesn't finish them: they reel back a little, then go to cover by their car.
func _stagger(o: Node3D, from: Vector3) -> void:
	var away := o.global_position - from
	away.y = 0.0
	if away.length() > 0.01:
		o.global_position += away.normalized() * float(combat("stagger_push_m", 0.5))
	o.set_meta("stagger_t", float(combat("stagger_s", 0.5)))
	o.set_meta("cover_until", _clock + float(combat("stagger_s", 0.5)) + float(combat("cover_s", 3.0)))
	_hold_pose(o, stagger_pose(), {})


## While staggering: no moving, no firing. Returns true while it lasts.
func _step_stagger(o: Node3D, delta: float) -> bool:
	var t := float(o.get_meta("stagger_t", 0.0))
	if t <= 0.0:
		return false
	t -= delta
	o.set_meta("stagger_t", t)
	if t <= 0.0:
		_release_pose(o)
	return true


## Where a hit officer shelters: beside their car on the side away from the player, while
## `cover_s` lasts; Vector3.INF when they aren't taking cover (or have no car).
func cover_point(o: Node3D) -> Vector3:
	if _clock >= float(o.get_meta("cover_until", -INF)):
		return Vector3.INF
	var car := _car_of(o)
	var target := _target()
	if car == null or target == null:
		return Vector3.INF
	var away := car.global_position - target.global_position
	away.y = 0.0
	if away.length() < 0.01:
		return Vector3.INF
	return car.global_position + away.normalized() * float(combat("cover_m", 2.0))


## Down as a ragdoll where the tone allows it; stays down until the chase ends.
func _knock_down(o: Node3D, impulse: Vector3, point: Vector3) -> void:
	_leave_fight(o, "down")
	var rig: CharacterRig = o.get_meta("rig")
	var rd := CharacterRagdoll.new()
	rd.name = "Ragdoll"
	o.add_child(rd)
	rd.begin(rig.profile, rig.global_transform, rig.phase, rig.amount)
	rd.apply_impulse(impulse, point, float(combat("down_spread", 0.6)))
	rig.visible = false
	o.set_meta("ragdoll", rd)
	o.set_meta("settle_t", float(combat("down_settle_s", 3.0)))


## Tagged out (no violence): sits on the ground with their hands up for `tag_out_s`, then walks
## back to their car.
func _tag_out(o: Node3D) -> void:
	_leave_fight(o, "tagged")
	var rig: CharacterRig = o.get_meta("rig")
	rig.position.y = -float(combat("sit_drop_m", 0.72)) * float(rig.profile.get("height", 1.0))
	_hold_pose(o, hands_up_pose(), sit_pose())
	o.set_meta("tag_t", float(combat("tag_out_s", 8.0)))


## Out of the fight: off the officers list (no moving on the player, no seeing them, no
## busting), the body can't be hit again and the weapon is put away.
func _leave_fight(o: Node3D, state: String) -> void:
	officers.erase(o)
	_officer_cooldown.erase(o)
	downed.append(o)
	o.set_meta("state", state)
	o.set_meta("stagger_t", 0.0)
	var body: OfficerBody = o.get_meta("body") if o.has_meta("body") else null
	if body != null:
		body.disable()
	var held: HeldWeapon = o.get_meta("held") if o.has_meta("held") else null
	if held != null:
		held.set_weapon({})
		held.aiming = false


## One step for an officer out of the fight: a ragdoll settles; a tagged-out officer waits,
## then walks back to the car and gets in (or leaves when the car is gone).
func _step_out_of_action(o: Node3D, delta: float) -> void:
	if not is_instance_valid(o):
		downed.erase(o)
		return
	match str(o.get_meta("state", "")):
		"down":
			var t := float(o.get_meta("settle_t", 0.0)) - delta
			o.set_meta("settle_t", t)
			var rd: CharacterRagdoll = o.get_meta("ragdoll") if o.has_meta("ragdoll") else null
			if t <= 0.0 and rd != null and not rd.is_settled():
				rd.settle()
		"tagged":
			var t := float(o.get_meta("tag_t", 0.0)) - delta
			o.set_meta("tag_t", t)
			if t <= 0.0:
				var rig: CharacterRig = o.get_meta("rig")
				rig.position.y = 0.0
				_release_pose(o)
				o.set_meta("state", "returning")
		"returning":
			_walk_back(o, delta)


## A tagged-out officer back on their feet walks to their car and gets in (or leaves when the
## car is gone); the car drives again.
func _walk_back(o: Node3D, delta: float) -> void:
	var car := _car_of(o)
	if car == null:
		downed.erase(o)
		o.queue_free()
		return
	var to := car.global_position - o.global_position
	to.y = 0.0
	if to.length() <= float(cfg("officer_board_m", 2.5)):
		downed.erase(o)
		o.queue_free()
		car.remove_meta("officer_out")
		return
	var speed := float(cfg("officer_speed_mps", 4.2)) * float(combat("return_speed", 0.5))
	o.global_position += to.normalized() * minf(speed * delta, to.length())
	o.look_at(Vector3(car.global_position.x, o.global_position.y, car.global_position.z), Vector3.UP)
	(o.get_meta("rig") as CharacterRig).advance(delta, speed)


## Another patrol car, sent to where an officer went out of the fight (up to `backup_extra`
## over the usual count).
func _call_backup(at: Vector3) -> void:
	var cap := int(cfg("max_police", 4)) + int(combat("backup_extra", 1))
	if cars.size() < cap:
		_spawn_car(at, at)


## Holds a pose on an officer's rig: arms from `arms`, legs from `legs` (either may be empty).
## The held weapon stops posing the arms until `_release_pose`.
func _hold_pose(o: Node3D, arms: Dictionary, legs: Dictionary) -> void:
	var held: HeldWeapon = o.get_meta("held") if o.has_meta("held") else null
	if held != null:
		held.process_mode = Node.PROCESS_MODE_DISABLED
	var rig: CharacterRig = o.get_meta("rig")
	rig.bone_override = arms
	rig.override_weight = 1.0 if not arms.is_empty() else 0.0
	rig.leg_override = legs
	rig.leg_weight = 1.0 if not legs.is_empty() else 0.0
	rig.repose()


func _release_pose(o: Node3D) -> void:
	var rig: CharacterRig = o.get_meta("rig")
	rig.override_weight = 0.0
	rig.leg_weight = 0.0
	rig.repose()
	var held: HeldWeapon = o.get_meta("held") if o.has_meta("held") else null
	if held != null:
		held.process_mode = Node.PROCESS_MODE_INHERIT


## Reeling from a hit: the body leans back (a positive turn about X tips the bone's top toward
## +Z, behind the body, which faces -Z) and the arms fly out to the sides (about Z, outward on
## each side).
static func stagger_pose() -> Dictionary:
	return {
		"spine": Quaternion(Vector3.RIGHT, 0.32),
		"head": Quaternion(Vector3.RIGHT, 0.22),
		"upper_arm_l": Quaternion(Vector3.BACK, 0.75) * Quaternion(Vector3.RIGHT, 0.35),
		"upper_arm_r": Quaternion(Vector3.BACK, -0.75) * Quaternion(Vector3.RIGHT, 0.35),
		"forearm_l": Quaternion(Vector3.RIGHT, 0.5),
		"forearm_r": Quaternion(Vector3.RIGHT, 0.5),
	}


## Hands up: both upper arms raised overhead, forearms bent a little.
static func hands_up_pose() -> Dictionary:
	return {
		"upper_arm_l": Quaternion(Vector3.RIGHT, 2.85),
		"upper_arm_r": Quaternion(Vector3.RIGHT, 2.85),
		"forearm_l": Quaternion(Vector3.RIGHT, 0.35),
		"forearm_r": Quaternion(Vector3.RIGHT, 0.35),
	}


## Sitting on the ground: thighs forward and level, shins out in front.
static func sit_pose() -> Dictionary:
	return {
		"thigh_l": Quaternion(Vector3.RIGHT, 1.5),
		"thigh_r": Quaternion(Vector3.RIGHT, 1.5),
		"shin_l": Quaternion(Vector3.RIGHT, -0.15),
		"shin_r": Quaternion(Vector3.RIGHT, -0.15),
	}


## Where the police are, for the minimap: [{"at": Vector3, "kind": "car" | "officer" |
## "helicopter", "sees": bool, "searching": bool}]. `sees`: that unit has the player now
## (ground units within `police_sight_m`, the helicopter by its own sight); `searching`: the
## helicopter is circling where it lost them.
func markers() -> Array:
	var out: Array = []
	var target := _target()
	var sight := wanted.sight_m() if wanted != null else float(cfg("police_sight_m", 55.0))
	for car in cars:
		if is_instance_valid(car):
			out.append({"at": car.global_position, "kind": "car", "sees": _within(car, target, sight), "searching": false})
	for officer in officers:
		if is_instance_valid(officer):
			out.append({"at": officer.global_position, "kind": "officer", "sees": _within(officer, target, sight), "searching": false})
	if helicopter != null and is_instance_valid(helicopter):
		out.append({"at": helicopter.global_position, "kind": "helicopter", "sees": helicopter.sees_target(), "searching": helicopter.searching()})
	return out


static func _within(unit: Node3D, target: Node3D, metres: float) -> bool:
	return target != null and unit.global_position.distance_to(target.global_position) <= metres


func _on_helicopter_landed() -> void:
	if helicopter != null:
		helicopter.queue_free()
		helicopter = null
	if stolen_helicopter == null:
		park_helicopter()  # back on its pad, ready to be called out (or taken)


func _remove_car(car: VehicleBody3D) -> void:
	cars.erase(car)
	_plans.erase(car)
	car.queue_free()


func _clear_all() -> void:
	for car in cars.duplicate():
		_remove_car(car)
	for o in officers:
		if is_instance_valid(o):
			o.queue_free()
	officers.clear()
	for o in downed:
		if is_instance_valid(o):
			o.queue_free()
	downed.clear()
	_officer_cooldown.clear()


## Everything gone at once (busted, wasted).
func reset() -> void:
	_clear_all()
	_busted_s = 0.0
	if helicopter != null:
		helicopter.queue_free()
		helicopter = null
		if stolen_helicopter == null:
			park_helicopter()
	if wanted != null:
		wanted.helicopter_sees = false


func _fill_siren() -> void:
	var pb := _siren.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var nearest := INF
	if player != null:
		for car in cars:
			if is_instance_valid(car):
				nearest = minf(nearest, car.global_position.distance_to(player.global_position))
	var gain := clampf(1.0 - nearest / 180.0, 0.0, 1.0)
	if gain <= 0.0 and not _siren_on:
		return
	_siren_on = gain > 0.0
	var frames := pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(frames)
	var t0 := _flash
	for i in range(frames):
		var t := t0 + float(i) / Synth.MIX_RATE
		var f := 650.0 + 350.0 * sin(t * TAU * 0.45)  # a slow wail
		_siren_phase += TAU * f / Synth.MIX_RATE
		var s := (1.0 if fmod(_siren_phase, TAU) < PI else -1.0) * 0.18 * gain
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)
	if _siren_phase > 1000.0 * TAU:
		_siren_phase = fmod(_siren_phase, TAU)


## The helicopter's rotor: a low noise thump at about 18 beats a second, louder as it nears.
func _fill_rotor() -> void:
	var pb := _rotor_voice.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null or helicopter == null or player == null:
		return
	var gain := clampf(1.0 - helicopter.global_position.distance_to(player.global_position) / 250.0, 0.0, 1.0)
	var frames := pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(frames)
	var step := FlyableHelicopter.rotor_phase_step(18.0, 1.0 / Synth.MIX_RATE)
	for i in range(frames):
		_rotor_phase = FlyableHelicopter.advance_phase(_rotor_phase, step)
		var beat := pow(maxf(sin(_rotor_phase), 0.0), 3.0)
		var s := Synth.noise(_noise_state) * beat * 0.5 * gain
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)
