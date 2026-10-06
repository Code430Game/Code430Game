class_name AmbulanceManager
extends Node3D
## Ambulances answer the injured (add-ambulance-response). Someone knocked down files a call
## after `call_delay_s`; calls within `merge_m` of an open one join it. Up to `max_out`
## ambulances drive out at once, from the nearest ambulance post or hospital within
## `base_reach_m` by road, or from out of view on the way in when none is that close. They run
## lights and siren, follow a road-graph route (RoadRoute), and stop by the person. Two
## paramedics walk over and tend to them for `tend_s`; then, by tone, the person gets up and
## walks off (clean), goes on a stretcher (gritty) or is lifted away by a drone (dystopia).
## The paramedics get back in and the ambulance heads home, freed once it reaches its base or
## is `leave_m` from the player. A downed person with a call open is held, not cleared, until
## the ambulance has been or `hold_max_s` runs out.

## A car hit the ambulance hard (the scene decides whether it was the player and an offence).
signal rammed(by: Node3D, at: Vector3)

const CAR_SCENE := preload("res://actors/vehicles/placeholder_car.tscn")
const CONFIG_PATH := "res://actors/emergency/ambulance_config.json"
const REPLAN_S := 2.0
const STEER_GAIN := 1.6
const VEHICLE_WHITE := Color(0.95, 0.95, 0.95)
const PULL_OUT_M := 20.0  # leaving a base: start this far down the road, clear of its driveway
const CLEAR_M := 10.0  # never start on top of another ambulance
const REVERSE_S := 1.2
const STALL_WINDOW_S := 1.5
const AHEAD_M := 8.0
const BLOCKED_KPH := 10.0
const STALL_MOVE_M := 2.0

enum Phase { DRIVE, TEND, RETURN }


class Call:
	extends RefCounted
	var at: Vector3
	var people: Array[Pedestrian] = []
	var age: float = 0.0
	var run: Run = null


class Run:
	extends RefCounted
	var car: VehicleBody3D
	var call: Call
	var phase: int = Phase.DRIVE
	var home: Vector3
	var points: PackedVector3Array = PackedVector3Array()
	var i: int = 0
	var age: float = REPLAN_S
	var reverse: float = 0.0  # seconds left backing out of something
	var window: float = 0.0  # stall check: seconds into the current window
	var window_from: Vector3 = Vector3.INF  # where the window started
	var stalls: int = 0  # windows in a row it barely moved
	var medics: Array[Node3D] = []
	var t: float = 0.0
	var carried: Node3D = null  # the stretcher or the drone


var config: Dictionary = {}
var peds: PedestrianManager
var graph: RoadGraph
var holder: Node3D  # where ambulances and paramedics live (the world)
var bases: Array = []  # Services.Place of kind ambulance or hospital
var player: Node3D  # whose ears the siren is for
var calls: Array[Call] = []
var runs: Array[Run] = []
var _flash: float = 0.0
var _siren: AudioStreamPlayer
var _siren_phase: float = 0.0
var _siren_t: float = 0.0
var _rng := RandomNumberGenerator.new()
## Prints calls and ambulances each second (the testbed's --ambulance-log).
var log_runs: bool = false
var _log_s: float = 0.0


func _ready() -> void:
	_rng.seed = 911
	if config.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		config = data if data is Dictionary else {}
	_siren = Synth.make_player("SFX", -14.0)
	add_child(_siren)
	_siren.play()
	if peds != null:
		peds.downed.connect(report)


func cfg(key: String, fallback: Variant) -> Variant:
	return config.get(key, fallback)


## A person is down: joins the open call nearby, or opens one.
func report(a: Pedestrian) -> void:
	a.held = true
	var merge := float(cfg("merge_m", 14.0))
	for c in calls:
		if (c.run == null or c.run.phase == Phase.DRIVE) and c.at.distance_to(a.position()) <= merge:
			c.people.append(a)
			return
	var c := Call.new()
	c.at = a.position()
	c.people.append(a)
	calls.append(c)


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	_flash += delta
	for c in calls.duplicate():
		_step_call(c, delta)
	for r in runs.duplicate():
		_step_run(r, delta)
	if log_runs:
		_log_s += delta
		if _log_s >= 1.0:
			_log_s = 0.0
			var line := "ambulances: calls %d runs %d" % [calls.size(), runs.size()]
			for r in runs:
				if is_instance_valid(r.car):
					var goal: Vector3 = r.call.at if r.call != null else r.home
					line += " | %s d %.0f v %.0f medics %d" % [Phase.keys()[r.phase], _flat(r.car.global_position, goal), float(r.car.call("speed_kph")), r.medics.size()]
			print(line)


func _step_call(c: Call, delta: float) -> void:
	c.age += delta
	# People cleared away by something else (they walked out of range of every player).
	for a in c.people.duplicate():
		if peds == null or not peds.agents.has(a):
			c.people.erase(a)
	if not c.people.is_empty():
		c.at = c.people[0].position()
	if c.people.is_empty() or c.age > float(cfg("hold_max_s", 150.0)):
		_close(c)
		return
	if c.run == null and c.age >= float(cfg("call_delay_s", 3.0)) and runs.size() < int(cfg("max_out", 2)):
		_dispatch(c)


func _close(c: Call) -> void:
	for a in c.people:
		a.held = false
	calls.erase(c)
	if c.run != null:
		c.run.call = null
		if c.run.phase != Phase.TEND:
			_go_home(c.run)


## Sends an ambulance to `c`: from the nearest base it can reach within `base_reach_m`, else
## from a point out of view on a route toward it. Returns false when nothing can get there.
func _dispatch(c: Call) -> bool:
	if graph == null:
		return false
	var start := Vector3.INF
	var home := Vector3.INF
	var facing := c.at
	var reach := float(cfg("base_reach_m", 900.0))
	var sorted := bases.duplicate()
	sorted.sort_custom(func(x: Variant, y: Variant) -> bool: return x.at.distance_to(c.at) < y.at.distance_to(c.at))
	for b in sorted:
		var node: RoadGraph.RoadNode = graph.nodes.get(b.road_node)
		var from: Vector3 = node.position if node != null else b.at
		var path := RoadRoute.find(graph, from, c.at)
		if path.is_empty():
			continue
		home = from
		if _length(path) <= reach:
			start = _pull_out_point(path)
		else:
			start = _point_out_of_view(path, c.at)
		facing = _next_after(path, start)
		break
	if start == Vector3.INF:
		start = _ring_node(c.at)
		home = start
	if start == Vector3.INF:
		return false
	var car: VehicleBody3D = CAR_SCENE.instantiate()
	car.set("vehicle_id", "ambulance")
	holder.add_child(car)
	car.global_position = start + Vector3.UP * 0.6
	car.call("set_body_color", VEHICLE_WHITE)
	var look := Vector3(facing.x, car.global_position.y, facing.z)
	if look.distance_to(car.global_position) > 0.5:
		car.look_at(look, Vector3.UP)
	if car.has_method("add_headlights"):
		car.add_headlights(false)
		car.set_headlights(1.0)
	car.add_child(light_bar(float(car.get("height")) if car.get("height") != null else 2.3))
	car.set_meta("ambulance", true)
	car.contact_monitor = true
	car.max_contacts_reported = 4
	car.body_entered.connect(_on_car_hit.bind(car))
	var r := Run.new()
	r.car = car
	r.call = c
	r.home = home
	c.run = r
	runs.append(r)
	return true


## Metres of route left from the car to the end of its current plan (0 before the first one).
func _route_left(r: Run) -> float:
	if r.points.is_empty():
		return 0.0
	var total := r.car.global_position.distance_to(r.points[r.i])
	for k in range(r.i, r.points.size() - 1):
		total += r.points[k].distance_to(r.points[k + 1])
	return total


static func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for k in range(path.size() - 1):
		total += path[k].distance_to(path[k + 1])
	return total


## Leaving a base along `path`: the first route point `PULL_OUT_M` from it with no other
## ambulance within `CLEAR_M` (a base's road node is often on its own driveway).
func _pull_out_point(path: PackedVector3Array) -> Vector3:
	for k in range(path.size() - 1):
		if path[k].distance_to(path[0]) >= PULL_OUT_M and _clear(path[k]):
			return path[k]
	return path[0] if _clear(path[0]) else path[path.size() - 2] if path.size() >= 2 else path[0]


func _clear(p: Vector3) -> bool:
	for r in runs:
		if is_instance_valid(r.car) and r.car.global_position.distance_to(p) < CLEAR_M:
			return false
	return true


## The route point after `p` (where a car starting at `p` faces).
static func _next_after(path: PackedVector3Array, p: Vector3) -> Vector3:
	for k in range(path.size() - 1):
		if path[k].is_equal_approx(p):
			return path[k + 1]
	return path[path.size() - 1]


## Walking back from the call along `path`: the first route point at least `spawn_min_m`
## away that the camera cannot see (or `spawn_max_m` away, seen or not).
func _point_out_of_view(path: PackedVector3Array, goal: Vector3) -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var lo := float(cfg("spawn_min_m", 130.0))
	var hi := float(cfg("spawn_max_m", 220.0))
	for k in range(path.size() - 1, -1, -1):
		var d := path[k].distance_to(goal)
		if d < lo:
			continue
		if (d >= hi or cam == null or not cam.is_position_in_frustum(path[k])) and _clear(path[k]):
			return path[k]
	return path[0]


## A road node in the spawn ring around `goal` that routes there, for a pack with no bases.
func _ring_node(goal: Vector3) -> Vector3:
	var ids := graph.nodes.keys()
	if ids.is_empty():
		return Vector3.INF
	var lo := float(cfg("spawn_min_m", 130.0))
	var hi := float(cfg("spawn_max_m", 220.0))
	for k in range(60):
		var n: RoadGraph.RoadNode = graph.nodes[ids[_rng.randi_range(0, ids.size() - 1)]]
		var d := n.position.distance_to(goal)
		if d >= lo and d <= hi and not RoadRoute.find(graph, n.position, goal).is_empty():
			return n.position
	return Vector3.INF


func _step_run(r: Run, delta: float) -> void:
	if not is_instance_valid(r.car):
		_free_run(r)
		return
	match r.phase:
		Phase.DRIVE:
			var goal := r.call.at
			var d := _flat(r.car.global_position, goal)
			if d <= float(cfg("stop_m", 9.0)):
				_arrive(r)
				return
			if d <= float(cfg("walk_up_m", 70.0)) and _route_left(r) > d * 2.5 + 40.0:
				_arrive(r)  # the road goes the long way round (a barrier, a divided road): walk over
				return
			_follow(r, goal, delta, float(cfg("cruise_kph", 75.0)))
			if _stalled(r, delta):
				if d <= float(cfg("walk_up_m", 70.0)):
					_arrive(r)  # boxed in close by: they walk the rest
				else:
					var c := r.call
					_free_run(r)
					c.run = null  # sent again from a fresh spot
		Phase.TEND:
			_brake(r.car)
			_step_tend(r, delta)
		Phase.RETURN:
			_follow(r, r.home, delta, float(cfg("cruise_kph", 75.0)) * 0.7)
			var far := player != null and r.car.global_position.distance_to(player.global_position) > float(cfg("leave_m", 280.0))
			if far or _stalled(r, delta) or _flat(r.car.global_position, r.home) <= float(cfg("home_m", 15.0)):
				_free_run(r)


## Stall check in windows of STALL_WINDOW_S: a window in which the car moved under
## STALL_MOVE_M backs it out for REVERSE_S; `stall_windows` such windows in a row means it is
## properly stuck (true).
func _stalled(r: Run, delta: float) -> bool:
	if r.window_from == Vector3.INF:
		r.window_from = r.car.global_position
	r.window += delta
	if r.window < STALL_WINDOW_S:
		return false
	var moved := r.car.global_position.distance_to(r.window_from)
	r.window = 0.0
	r.window_from = r.car.global_position
	if moved >= STALL_MOVE_M:
		r.stalls = 0
		return false
	r.stalls += 1
	r.reverse = REVERSE_S
	return r.stalls >= int(cfg("stall_windows", 4))


func _arrive(r: Run) -> void:
	r.phase = Phase.TEND
	r.t = 0.0
	_brake(r.car)
	var side := r.car.global_basis.x
	for k in range(2):
		r.medics.append(_make_medic(r.car.global_position + side * (1.6 if k == 0 else -1.6) + r.car.global_basis.z * 2.0, k))


## Paramedics walk to the person, kneel for `tend_s`, then the tone decides what happens and
## they walk back to the ambulance.
func _step_tend(r: Run, delta: float) -> void:
	var speed := float(cfg("medic_speed_mps", 2.6))
	var back := r.call == null or r.t >= float(cfg("tend_s", 5.0))
	var at: Vector3 = r.call.at if r.call != null else r.car.global_position
	var all_there := true
	for k in range(r.medics.size()):
		var m := r.medics[k]
		var goal := at + Vector3(0.75 if k == 0 else -0.75, 0, 0.2)
		if back:  # the rear doors
			goal = r.car.global_position + r.car.global_basis.z * 3.0 + r.car.global_basis.x * (0.5 if k == 0 else -0.5)
		all_there = _walk(m, goal, speed, delta) and all_there
		if not back and _flat(m.global_position, goal) < 0.4:
			_face(m, at)
	if r.carried != null:
		_step_carried(r, delta)
	if not back:
		if all_there:
			r.t += delta
			for m in r.medics:
				(m.get_meta("rig") as CharacterRig).position.y = -0.45  # kneeling
			if r.carried == null and ContentMode.current == "dystopia":
				r.carried = _make_drone(at)
			if r.t >= float(cfg("tend_s", 5.0)):
				_finish_tending(r)
		return
	if all_there:
		for m in r.medics:
			m.queue_free()
		r.medics.clear()
		if r.carried != null and r.carried.has_meta("stretcher"):
			r.carried.queue_free()
			r.carried = null
		_go_home(r)


## Tending is done: the result for the tone, then the call closes.
func _finish_tending(r: Run) -> void:
	for m in r.medics:
		(m.get_meta("rig") as CharacterRig).position.y = 0.0
	var c := r.call
	if c == null:
		return
	match ContentMode.current:
		"clean":
			for a in c.people.duplicate():
				peds.revive(a)
		"dystopia":
			for a in c.people.duplicate():
				peds.carry_off(a)
			if r.carried != null:
				r.carried.set_meta("lifting", true)
		_:
			for a in c.people.duplicate():
				peds.carry_off(a)
			r.carried = _make_stretcher()
	c.people.clear()
	calls.erase(c)
	c.run = null
	r.call = null
	r.t = float(cfg("tend_s", 5.0))


func _step_carried(r: Run, delta: float) -> void:
	var n := r.carried
	if n.has_meta("stretcher"):
		if r.medics.size() == 2:
			var a := r.medics[0].global_position
			var b := r.medics[1].global_position
			n.global_position = (a + b) * 0.5 + Vector3.UP * 0.8
			if a.distance_to(b) > 0.2:
				n.look_at(n.global_position + (b - a).cross(Vector3.UP), Vector3.UP)
		return
	# The drone: down to just above the person while they are tended, then up and away.
	var goal: Vector3 = n.get_meta("over")
	if n.has_meta("lifting"):
		n.global_position += Vector3.UP * 9.0 * delta
		if n.global_position.y > goal.y + 45.0:
			n.queue_free()
			r.carried = null
	else:
		n.global_position = n.global_position.move_toward(goal + Vector3.UP * 2.2, 8.0 * delta)
	n.rotate_y(delta * 2.0)


func _go_home(r: Run) -> void:
	r.phase = Phase.RETURN
	r.age = REPLAN_S
	r.stalls = 0
	r.window = 0.0
	r.window_from = Vector3.INF
	var bar: Node3D = r.car.get_node_or_null("LightBar") if is_instance_valid(r.car) else null
	if bar != null:
		bar.visible = false


func _free_run(r: Run) -> void:
	runs.erase(r)
	for m in r.medics:
		if is_instance_valid(m):
			m.queue_free()
	r.medics.clear()
	if r.carried != null and is_instance_valid(r.carried):
		r.carried.queue_free()
	r.carried = null
	if is_instance_valid(r.car):
		r.car.queue_free()
	if r.call != null:
		r.call.run = null


## Everything gone at once (the scene resets: busted, wasted, a new game).
func reset() -> void:
	for r in runs.duplicate():
		_free_run(r)
	for c in calls:
		for a in c.people:
			a.held = false
	calls.clear()


## Every ambulance body, for traffic to stop for like a player's car.
func bodies() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for r in runs:
		if is_instance_valid(r.car):
			out.append(r.car)
	return out


## Ambulances driving to a call with lights and siren (walkers wait at crossings for them).
func calling_bodies() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for r in runs:
		if r.phase == Phase.DRIVE and is_instance_valid(r.car):
			out.append(r.car)
	return out


## Ambulances on a call (lights on), for the minimap.
func positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for r in runs:
		if r.phase != Phase.RETURN and is_instance_valid(r.car):
			out.append(r.car.global_position)
	return out


func _follow(r: Run, goal: Vector3, delta: float, cruise: float) -> void:
	var car := r.car
	if r.reverse > 0.0:
		# Back out of whatever stopped it, wheels turned the other way.
		r.reverse -= delta
		var back_to := car.to_local(goal)
		car.set("override_steer", -clampf(atan2(-back_to.x, -back_to.z) * STEER_GAIN, -1.0, 1.0))
		car.set("override_throttle", 0.0)
		car.set("override_brake", 1.0)
		return
	r.age += delta
	if r.age >= REPLAN_S:
		r.age = 0.0
		r.points = RoadRoute.find(graph, car.global_position, goal)
		var nearest := 0
		for k in range(r.points.size()):
			if car.global_position.distance_to(r.points[k]) < car.global_position.distance_to(r.points[nearest]):
				nearest = k
		r.i = mini(nearest + 1, maxi(r.points.size() - 1, 0))
	while r.i < r.points.size() - 1 and car.global_position.distance_to(r.points[r.i]) < 8.0:
		r.i += 1
	var aim := goal if r.points.is_empty() else r.points[r.i]
	var local := car.to_local(aim)
	car.set("override_steer", clampf(atan2(-local.x, -local.z) * STEER_GAIN, -1.0, 1.0))
	var d := _flat(car.global_position, goal)
	var limit := clampf(d * 1.5, 12.0, cruise)
	if _blocked_ahead(car):
		limit = minf(limit, BLOCKED_KPH)  # creep, don't ram (traffic stops for it, and pulls on)
	var speed := float(car.call("speed_kph"))
	car.set("override_brake", 1.0 if speed > limit + 15.0 else 0.0)
	car.set("override_throttle", 1.0 if speed < limit else 0.0)


## Something solid that moves (a car, another ambulance) within AHEAD_M in front.
func _blocked_ahead(car: VehicleBody3D) -> bool:
	if not is_inside_tree():
		return false
	var fwd := -car.global_basis.z
	var from := car.global_position + Vector3.UP * 0.9 + fwd * (float(car.get("length_m")) * 0.5 if car.get("length_m") != null else 2.6)
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * AHEAD_M)
	q.exclude = [car.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] is RigidBody3D


static func _brake(car: VehicleBody3D) -> void:
	car.set("override_steer", 0.0)
	car.set("override_throttle", 0.0)
	car.set("override_hold", true)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Moves a paramedic toward `goal`. True once there.
func _walk(m: Node3D, goal: Vector3, speed: float, delta: float) -> bool:
	var to := goal - m.global_position
	to.y = 0.0
	var d := to.length()
	var moving := d > 0.3
	if moving:
		m.global_position += to.normalized() * minf(speed * delta, d)
		_face(m, goal)
	m.global_position.y = lerpf(m.global_position.y, _ground(m.global_position, goal.y), clampf(delta * 8.0, 0.0, 1.0))
	var rig := m.get_meta("rig") as CharacterRig
	rig.advance(delta, speed if moving else 0.0)
	if moving:
		rig.position.y = 0.0
	return not moving


## The walkable surface under `p` (static geometry only), or `fallback` when there is none.
func _ground(p: Vector3, fallback: float) -> float:
	if not is_inside_tree():
		return fallback
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 4.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit["collider"] is StaticBody3D):
		return fallback
	return float((hit["position"] as Vector3).y)


static func _face(m: Node3D, point: Vector3) -> void:
	var flat := Vector3(point.x, m.global_position.y, point.z)
	if flat.distance_to(m.global_position) > 0.1:
		m.look_at(flat, Vector3.UP)  # bodies face -Z


func _make_medic(at: Vector3, k: int) -> Node3D:
	var m := Node3D.new()
	m.name = "Paramedic"
	var rig := CharacterRig.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 300 + runs.size() * 2 + k
	var p := CharacterProfile.random(rng)
	p["top"] = 2  # green
	p["bottom"] = 2
	p["jacket"] = 1
	p["jacket_colour"] = 3  # yellow high-visibility
	p["hat"] = 0
	rig.profile = p
	m.add_child(rig)
	m.set_meta("rig", rig)
	holder.add_child(m)
	m.global_position = at
	return m


func _make_stretcher() -> Node3D:
	var s := Node3D.new()
	s.name = "Stretcher"
	s.set_meta("stretcher", true)
	s.add_child(_box(Vector3(0.6, 0.12, 2.0), Color(0.92, 0.92, 0.9)))
	var person := _box(Vector3(0.45, 0.28, 1.6), Color(0.35, 0.5, 0.7))  # a blanket over them
	person.position = Vector3(0, 0.18, 0)
	s.add_child(person)
	holder.add_child(s)
	return s


func _make_drone(over: Vector3) -> Node3D:
	var d := Node3D.new()
	d.name = "MedicalDrone"
	d.set_meta("over", over)
	d.add_child(_box(Vector3(1.4, 0.35, 1.4), Color(0.85, 0.88, 0.92)))
	for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var arm := _box(Vector3(0.9, 0.06, 0.9), Color(0.1, 0.1, 0.12))
		arm.position = Vector3(corner.x * 0.9, 0.25, corner.y * 0.9)
		d.add_child(arm)
	var glow := _box(Vector3(1.0, 0.06, 1.0), Color(0.2, 0.95, 0.75))
	var mat := glow.material_override as StandardMaterial3D
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.95, 0.75)
	mat.emission_energy_multiplier = 3.0
	glow.position = Vector3(0, -0.2, 0)
	d.add_child(glow)
	holder.add_child(d)
	d.global_position = over + Vector3.UP * 40.0
	return d


## A red and white light bar for a roof at height `h`.
static func light_bar(h: float) -> Node3D:
	var bar := Node3D.new()
	bar.name = "LightBar"
	for side: float in [-1.0, 1.0]:
		var c := Color(1.0, 0.1, 0.1) if side < 0.0 else Color(1.0, 1.0, 1.0)
		var m := _box(Vector3(0.5, 0.14, 0.22), c)
		var mat := m.material_override as StandardMaterial3D
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 4.0
		m.position = Vector3(side * 0.4, h + 0.08, -1.6)
		var glow := OmniLight3D.new()
		glow.light_color = c
		glow.light_energy = 1.5
		glow.omni_range = 7.0
		m.add_child(glow)
		bar.add_child(m)
	return bar


static func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	return m


func _on_car_hit(body: Node, car: VehicleBody3D) -> void:
	if body is VehicleBody3D and body.has_method("speed_kph"):
		var rel := ((body as VehicleBody3D).linear_velocity - car.linear_velocity).length() * 3.6
		if rel >= float(cfg("ram_kph", 15.0)):
			rammed.emit(body, car.global_position)


func _process(_delta: float) -> void:
	# Light bars alternate red and white, a little faster than the police.
	var on := fmod(_flash * 4.0, 1.0) < 0.5
	for r in runs:
		if is_instance_valid(r.car) and r.phase != Phase.RETURN:
			var bar: Node3D = r.car.get_node_or_null("LightBar")
			if bar != null:
				(bar.get_child(0) as MeshInstance3D).visible = on
				(bar.get_child(1) as MeshInstance3D).visible = not on
	_fill_siren()


## A yelp: a fast up-and-down sweep, only while an ambulance on a call is in earshot.
func _fill_siren() -> void:
	var pb := _siren.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null or player == null:
		return
	var nearest := INF
	for r in runs:
		if is_instance_valid(r.car) and r.phase == Phase.DRIVE:
			nearest = minf(nearest, r.car.global_position.distance_to(player.global_position))
	var gain := clampf(1.0 - nearest / float(cfg("siren_hear_m", 200.0)), 0.0, 1.0)
	if gain <= 0.0:
		return
	var frames := pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(frames)
	for k in range(frames):
		_siren_t += 1.0 / Synth.MIX_RATE
		var sweep := absf(fmod(_siren_t * 3.2, 2.0) - 1.0)  # triangle, 1.6 sweeps a second
		var f := 800.0 + 700.0 * sweep
		_siren_phase += TAU * f / Synth.MIX_RATE
		var s := (2.0 * absf(fmod(_siren_phase / TAU, 1.0) * 2.0 - 1.0) - 1.0) * 0.2 * gain
		buf[k] = Vector2(s, s)
	pb.push_buffer(buf)
	if _siren_phase > 1000.0 * TAU:
		_siren_phase = fmod(_siren_phase, TAU)
	if _siren_t > 1000.0:
		_siren_t = fmod(_siren_t, 2.0)
