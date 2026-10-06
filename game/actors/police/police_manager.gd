class_name PoliceManager
extends Node3D
## The police response (add-police 2.2-2.4). With a wanted level it keeps `police_per_star`
## patrol cars chasing the player: they spawn out of view on a road node `spawn_min_m` to
## `spawn_max_m` away, follow a road-graph path toward the player (re-planned every couple of
## seconds) and drive straight at them once close, light bars flashing and a siren wailing.
## A stopped car near a player on foot, or near the player's own stopped car, lets an officer
## out who runs at them (or to the driver's door) and, at a player on foot, uses the officer
## weapon the tone gives (a net that holds the player in `clean`, a pistol or blaster at the
## top level elsewhere). Held still with an officer beside them for `busted_s`, the player is
## busted. Officers left far behind are dropped; cars and officers leave when the level clears.

signal busted
signal net_hit(seconds: float)
signal shot_at(damage: float)

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
## 0 day .. 1 night (the scene's day-night clock), for the helicopter's searchlight.
var night: float = 0.0
var _rotor_voice: AudioStreamPlayer
var _rotor_t: float = 0.0
var _noise_state: Array = [0x1234567]
var cars: Array[VehicleBody3D] = []
var officers: Array[Node3D] = []
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
			officers.erase(o)  # left far behind (the player drove off)
			_officer_cooldown.erase(o)
			o.queue_free()
			continue
		_step_officer(o, delta)
		positions.append(o.global_position)
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


func _spawn_car(around: Vector3) -> bool:
	if graph == null:
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
	car.look_at(Vector3(around.x, car.global_position.y, around.z), Vector3.UP)
	if car.has_method("add_headlights"):
		car.add_headlights(false)
		car.set_headlights(1.0)
	car.add_child(_light_bar(car))
	car.set_meta("police", true)
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
	var goal := target.global_position
	var d := car.global_position.distance_to(goal)
	var aim := goal
	if d > DIRECT_M:
		var plan: Dictionary = _plans.get(car, {})
		var age := float(plan.get("age", REPLAN_S)) + delta
		if age >= REPLAN_S:
			var pts_new := route(car.global_position, goal)
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
	if d < 7.0 and (not player.is_driving() or stopped_car):
		car.set("override_throttle", 0.0)
		car.set("override_hold", true)  # pull up beside a player on foot or a stopped car (brake alone would reverse)
	else:
		car.set("override_throttle", 1.0 if speed < limit else 0.0)


## Road-graph route from `from` to `to` (see RoadRoute.find).
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	return RoadRoute.find(graph, from, to)


## A car that has barely moved for STUCK_S while far from the player (wedged on a kerb, a
## wall, a deck it cannot leave) is taken away and sent in again from a fresh spot.
func _unstick(car: VehicleBody3D, target: Node3D, delta: float) -> void:
	var far := car.global_position.distance_to(target.global_position) > DIRECT_M
	if far and absf(float(car.call("speed_kph"))) < 3.0:
		var t := float(car.get_meta("stuck_s", 0.0)) + delta
		car.set_meta("stuck_s", t)
		if t >= STUCK_S:
			_remove_car(car)
	else:
		car.set_meta("stuck_s", 0.0)


func _maybe_let_out(target: Node3D) -> void:
	if officers.size() >= cars.size():
		return
	if player.is_driving() and absf(float(target.call("speed_kph"))) > float(cfg("officer_car_stopped_kph", 8.0)):
		return  # a car still moving: they stay in and chase
	for car in cars:
		if car.has_meta("officer_out"):
			continue
		if car.global_position.distance_to(target.global_position) < float(cfg("officer_get_out_m", 25.0)) and absf(float(car.call("speed_kph"))) < 6.0:
			car.set_meta("officer_out", true)
			officers.append(_make_officer(car.global_position + car.global_basis.x * 1.6))
			return


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
	return o


func _step_officer(o: Node3D, delta: float) -> void:
	var target := _target()
	var goal := target.global_position
	var to := goal - o.global_position
	to.y = 0.0
	var d := to.length()
	var speed := 0.0
	# Up to a player on foot, or to the driver's door of a stopped car.
	var stop := float(cfg("busted_m", 3.0)) * 0.6 if not player.is_driving() else float(cfg("officer_at_car_m", 2.4))
	if d > stop:
		speed = float(cfg("officer_speed_mps", 4.2))
		o.global_position += to.normalized() * speed * delta
	o.global_position.y = lerpf(o.global_position.y, target.global_position.y, clampf(delta * 6.0, 0.0, 1.0))
	if d > 0.1:
		o.look_at(Vector3(goal.x, o.global_position.y, goal.z), Vector3.UP)  # bodies face -Z
	(o.get_meta("rig") as CharacterRig).advance(delta, speed)
	# The tone's officer weapon.
	var cool := float(_officer_cooldown.get(o, 0.0)) - delta
	_officer_cooldown[o] = cool
	var w := WeaponSet.resolve(_officer_weapon)
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


## Three stars bring the helicopter from the nearest helipad (or high at the district edge);
## below three it goes home and is freed when it lands.
func _step_helicopter(target: Node3D) -> void:
	if wanted.stars >= 3 and helicopter == null:
		helicopter = PoliceHelicopter.new()
		helicopter.name = "PoliceHelicopter"
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
			helicopter.global_position = target.global_position + from + Vector3.UP * PoliceHelicopter.CRUISE_M
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


func _on_helicopter_landed() -> void:
	if helicopter != null:
		helicopter.queue_free()
		helicopter = null


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
	_officer_cooldown.clear()


## Everything gone at once (busted, wasted).
func reset() -> void:
	_clear_all()
	_busted_s = 0.0
	if helicopter != null:
		helicopter.queue_free()
		helicopter = null
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
	var dt := 1.0 / Synth.MIX_RATE
	for i in range(frames):
		_rotor_t += dt
		var beat := pow(maxf(sin(_rotor_t * TAU * 18.0), 0.0), 3.0)
		var s := Synth.noise(_noise_state) * beat * 0.5 * gain
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)
	if _rotor_t > 1000.0:
		_rotor_t = fmod(_rotor_t, 1.0)
