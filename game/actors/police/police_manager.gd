class_name PoliceManager
extends Node3D
## The police response (add-police 2.2-2.4). With a wanted level it keeps `police_per_star`
## patrol cars chasing the player: they spawn out of view on a road node `spawn_min_m` to
## `spawn_max_m` away, follow a road-graph path toward the player (re-planned every couple of
## seconds) and drive straight at them once close, light bars flashing and a siren wailing.
## A stopped car near a player on foot lets an officer out who runs at them and uses the
## officer weapon the tone gives (a net that holds the player in `clean`, a pistol or blaster
## at the top level elsewhere). Held still with an officer beside them for `busted_s`, the
## player is busted. Cars and officers leave when the level clears.

signal busted
signal net_hit(seconds: float)
signal shot_at(damage: float)

const CAR_SCENE := preload("res://actors/vehicles/placeholder_car.tscn")
const REPLAN_S := 2.0
const DIRECT_M := 35.0
const STEER_GAIN := 1.6
const STUCK_S := 3.0

var wanted: Wanted
var graph: RoadGraph
var player: Player
var holder: Node3D  # where cars and officers live (the world)
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
		_step_officer(o, delta)
		positions.append(o.global_position)
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


func _spawn_car(around: Vector3) -> bool:
	if graph == null:
		return false
	var lo := float(cfg("spawn_min_m", 90.0))
	var hi := float(cfg("spawn_max_m", 160.0))
	var cam := get_viewport().get_camera_3d()
	var best: RoadGraph.RoadNode = null
	var ids := graph.nodes.keys()
	for k in range(60):
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
	if d < 7.0 and not player.is_driving():
		car.set("override_throttle", 0.0)
		car.set("override_brake", 1.0)  # pull up beside a player on foot
	else:
		car.set("override_throttle", 1.0 if speed < limit else 0.0)


## Road-graph route from `from` to `to`: node positions along the cheapest path (police ignore
## one-way rules), ending at `to`. Empty when either end is off the network.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start := _nearest_node(from)
	var goal := _nearest_node(to)
	var out := PackedVector3Array()
	if start == "" or goal == "":
		return out
	var dist := {start: 0.0}
	var prev := {}
	var open: Array = [[0.0, start]]
	var goal_pos: Vector3 = graph.nodes[goal].position
	var steps := 0
	while not open.is_empty() and steps < 4000:
		steps += 1
		var best := 0
		for k in range(open.size()):
			if float(open[k][0]) < float(open[best][0]):
				best = k
		var cur: String = open[best][1]
		open.remove_at(best)
		if cur == goal:
			break
		for eid: String in graph.incident(cur):
			var e: RoadGraph.RoadEdge = graph.edges[eid]
			var nxt := e.to_node if e.from_node == cur else e.from_node
			var nd := float(dist[cur]) + e.length_m
			if nd < float(dist.get(nxt, INF)):
				dist[nxt] = nd
				prev[nxt] = cur
				open.append([nd + (graph.nodes[nxt] as RoadGraph.RoadNode).position.distance_to(goal_pos), nxt])
	if not prev.has(goal) and start != goal:
		return out
	var chain: Array[String] = [goal]
	while chain[0] != start:
		chain.push_front(prev[chain[0]])
	for nid in chain:
		out.append((graph.nodes[nid] as RoadGraph.RoadNode).position)
	out.append(to)
	return out


func _nearest_node(p: Vector3) -> String:
	var hit := graph.nearest_edge(p, 80.0)
	if hit.is_empty():
		return ""
	var e: RoadGraph.RoadEdge = hit["edge"]
	var a: Vector3 = graph.nodes[e.from_node].position
	var b: Vector3 = graph.nodes[e.to_node].position
	return e.from_node if a.distance_to(p) < b.distance_to(p) else e.to_node


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
	if player.is_driving() or officers.size() >= cars.size():
		return
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
	return o


func _step_officer(o: Node3D, delta: float) -> void:
	var goal := player.global_position
	var to := goal - o.global_position
	to.y = 0.0
	var d := to.length()
	var speed := 0.0
	if d > float(cfg("busted_m", 3.0)) * 0.6:
		speed = float(cfg("officer_speed_mps", 4.2))
		o.global_position += to.normalized() * speed * delta
	o.global_position.y = lerpf(o.global_position.y, player.global_position.y, clampf(delta * 6.0, 0.0, 1.0))
	if d > 0.1:
		o.look_at(Vector3(goal.x, o.global_position.y, goal.z), Vector3.UP)
		o.rotate_y(PI)
	(o.get_meta("rig") as CharacterRig).advance(delta, speed)
	# The tone's officer weapon.
	var cool := float(_officer_cooldown.get(o, 0.0)) - delta
	_officer_cooldown[o] = cool
	if cool > 0.0 or player.is_driving():
		return
	var w := WeaponSet.resolve(_officer_weapon)
	if w.is_empty():
		return
	var lethal := bool(w.get("lethal", false))
	if lethal and wanted.stars < int(cfg("fire_min_stars", 3)):
		return
	if d <= float(cfg("officer_fire_m", 22.0)):
		_officer_cooldown[o] = float(cfg("officer_rate_s", 1.1)) * (3.0 if not lethal else 1.0)
		if lethal:
			shot_at.emit(float(cfg("officer_damage", 9.0)))
		else:
			net_hit.emit(float(cfg("net_s", 3.0)))


func _check_busted(delta: float) -> void:
	var near := false
	var target := _target()
	for o in officers:
		if is_instance_valid(o) and o.global_position.distance_to(player.global_position) <= float(cfg("busted_m", 3.0)):
			near = true
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
