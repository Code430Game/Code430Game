class_name PedestrianManager
extends Node3D
## Spawns and walks pedestrians on a WalkGraph around the players.
##
## Agents are plain data (Pedestrian). One MultiMesh draws them all; a small pool of
## physics bodies follows the ones nearest the players so vehicles can hit them. Each
## physics step an agent advances along its path at its own pace, offset inside the
## ribbon, stops while a player stands right ahead, picks a connected path at the end
## (preferring to keep its heading) or turns around at a dead end. A hit pedestrian
## tumbles as a rigid body for the hit window, then lies still until removal. Agents
## far from every player step every Nth frame with a larger delta.

## A vehicle knocked a walker down (the police hear about it if someone saw).
signal struck_by_vehicle(agent: Pedestrian, vehicle: Node3D)
## Someone was knocked down, by anything (ambulances answer it).
signal downed(agent: Pedestrian)

const BODY_SCENE := preload("res://world/pedestrians/pedestrian_body.tscn")
const WALK_SHADER := preload("res://world/pedestrians/pedestrian_walk.gdshader")
const CONFIG_PATH := "res://world/pedestrians/pedestrian_config.json"

var config: Dictionary = {}
var walk: WalkGraph
## The road graph and traffic, for crossings: which road a crossing spans, its signal, and
## the cars approaching it. Optional; without them crossings are just paths.
var road_graph: RoadGraph
var traffic: TrafficManager
var max_agents: int = 120
var agents: Array[Pedestrian] = []
var rng := RandomNumberGenerator.new()
var enabled: bool = true
## Mirror mode (co-op clients): agents come from the host's snapshots; no spawning or stepping.
var mirror: bool = false
## Positions pedestrians are kept around (the players). Set each frame by the scene.
var anchors: PackedVector3Array = PackedVector3Array()
## Player bodies pedestrians stop for. Set each frame by the scene.
var obstacles: Array[Node3D] = []
## Emergency vehicles on a call (lights and siren): nobody steps onto a crossing they are
## bearing down on. Set each frame by the scene.
var emergency: Array[Node3D] = []
var _spawn_timer: float = 0.0
var _frame: int = 0
const POOLS := 8  # distinct body looks; agents are spread across them
const STARTLE_S := 1.5  # how long a walker stops to look at a horn
const FLEE_S := 6.0  # how long a painted or frightened walker runs
const FLEE_SPEED_MPS := 3.4
const STUMBLE_LEAN_RAD := 0.3  # how far a shoved walker rocks back
var _pools: Array[MultiMeshInstance3D] = []
var pool_profiles: Array[Dictionary] = []
var _last_snapshot_ms: int = 0
var _bodies: Array[PedestrianBody] = []
var _ragdolls: Array[CharacterRagdoll] = []


func _ready() -> void:
	if config.is_empty():
		load_config()
	rng.seed = 431


## Loads pedestrian_config.json. Returns false and logs when unreadable.
func load_config(path: String = CONFIG_PATH) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("PedestrianManager: cannot read %s" % path)
		return false
	config = parsed
	max_agents = int(config["max_agents"])
	return true


func setup(walk_graph: WalkGraph, graph: RoadGraph = null, traffic_manager: TrafficManager = null) -> void:
	walk = walk_graph
	road_graph = graph
	traffic = traffic_manager
	if graph != null:
		_link_crossings()
	_setup_rendering()


## Finds, for every crossing path, the road it crosses and the signalised junction it belongs to.
func _link_crossings() -> void:
	var linked := 0
	for p in walk.paths:
		if p.kind != "crossing":
			continue
		var mid := p.position_at(p.length * 0.5)
		var hit := road_graph.nearest_edge(mid, float(config.get("crossing_road_reach_m", 15.0)))
		if hit.is_empty():
			continue
		var e: RoadGraph.RoadEdge = hit["edge"]
		p.crossed_edge = e.id
		var reach := float(config.get("crossing_signal_reach_m", 35.0))
		for nid in [e.from_node, e.to_node]:
			if road_graph.is_signalised(nid) and road_graph.nodes[nid].position.distance_to(mid) <= reach:
				p.signal_node = nid
		linked += 1
	print("pedestrians: %d crossings linked to roads" % linked)


## True when a pedestrian may step onto `path` now: on the crossed road's red at a
## signalised junction, or when no car is bearing down on an uncontrolled crossing.
func crossing_open(path: WalkGraph.WalkPath) -> bool:
	if path.kind != "crossing" or path.crossed_edge == "":
		return true
	if not emergency.is_empty():
		var at := path.position_at(path.length * 0.5)
		var reach := float(config.get("emergency_gap_m", 45.0))
		for v in emergency:
			if not is_instance_valid(v):
				continue
			var rel := at - v.global_position
			if rel.length() < reach and rel.dot(-v.global_basis.z) > 0.0:
				return false  # lights and siren coming: wait (even on a green)
	if path.signal_node != "" and traffic != null:
		return traffic.signals.light(path.signal_node, path.crossed_edge) == TrafficManager.Signals.Light.RED
	if traffic == null:
		return true
	var mid := path.position_at(path.length * 0.5)
	var gap := float(config.get("crossing_gap_m", 25.0))
	for a in traffic.agents:
		if a.retired or a.speed < 1.0:
			continue
		var lane: LaneGraph.LanePath = traffic.lanes.paths[a.path_id]
		if lane.edge_id != path.crossed_edge:
			continue
		var rel := mid - a.position()
		if rel.length() < gap and rel.dot(-a.transform.basis.z) > 0.0:
			return false  # a car on this road, heading for the crossing, too close
	return true


## Positions of people currently on a crossing, for traffic to yield to.
func crossing_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for a in agents:
		if a.state == Pedestrian.State.WALKING and walk.paths[a.path_id].kind == "crossing":
			out.append(a.position())
	return out


func _setup_rendering() -> void:
	if not _pools.is_empty():
		return
	for i in range(POOLS):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (i + 1)
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true  # x = walk phase, y = walk amount (pedestrian_walk.gdshader)
		var profile := CharacterProfile.random(rng)
		pool_profiles.append(profile)
		mm.mesh = CharacterMesh.build(profile, {}, false, true)
		mm.mesh.surface_set_material(0, walk_material(profile))
		mm.instance_count = max_agents
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		add_child(mmi)
		_pools.append(mmi)
	for i in range(int(config["body_pool"])):
		var body: PedestrianBody = BODY_SCENE.instantiate()
		body.hit.connect(_on_body_hit)
		body.min_hit_speed = float(config.get("hit_min_speed_mps", 1.5))
		add_child(body)
		body.process_mode = Node.PROCESS_MODE_DISABLED
		body.global_position = Vector3(0, -1000, 0)
		_bodies.append(body)
	for i in range(int(config.get("ragdoll_pool", 6))):
		var rd := CharacterRagdoll.new()
		rd.name = "Ragdoll%d" % i
		add_child(rd)
		_ragdolls.append(rd)


## The walk shader material for one body look: its bone pivots as the shader's uniform.
static func walk_material(profile: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WALK_SHADER
	var pivots := PackedVector3Array()
	for b in range(CharacterMesh.BONES.size()):
		pivots.append(CharacterMesh.bone_pivot(b, profile))
	mat.set_shader_parameter("pivots", pivots)
	return mat


func active_count() -> int:
	return agents.size()


## Exponential moving averages of this manager's per-tick costs, in milliseconds.
var profile: Dictionary = {"spawn_ms": 0.0, "step_ms": 0.0, "bodies_ms": 0.0, "render_ms": 0.0}


func _profile_add(key: String, usec: int) -> void:
	profile[key] = float(profile[key]) * 0.97 + float(usec) / 1000.0 * 0.03


## One-line summary of the profile for the benchmark.
func profile_line() -> String:
	return "spawn %.2f step %.2f bodies %.2f render %.2f ms" % [profile["spawn_ms"], profile["step_ms"], profile["bodies_ms"], profile["render_ms"]]


func _physics_process(delta: float) -> void:
	if mirror:
		for a in agents:
			var w := CharacterRig.step_walk(a.walk_phase, a.walk_amount, delta, a.speed)
			a.walk_phase = w.x
			a.walk_amount = w.y
		_assign_bodies()
		_render()
		return
	if walk == null or not enabled or anchors.is_empty():
		return
	_frame += 1
	_spawn_timer -= delta
	var t0 := Time.get_ticks_usec()
	if _spawn_timer <= 0.0:
		_spawn_timer = float(config["spawn_interval_s"])
		_despawn_far()
		for i in range(int(config["spawns_per_interval"])):
			if agents.size() >= max_agents:
				break
			_spawn_one()
	var t1 := Time.get_ticks_usec()
	step(delta)
	var t2 := Time.get_ticks_usec()
	_assign_bodies()
	var t3 := Time.get_ticks_usec()
	_render()
	var t4 := Time.get_ticks_usec()
	_profile_add("spawn_ms", t1 - t0)
	_profile_add("step_ms", t2 - t1)
	_profile_add("bodies_ms", t3 - t2)
	_profile_add("render_ms", t4 - t3)


## Advances every agent. Pure of spawning and rendering so tests can drive it directly.
func step(delta: float) -> void:
	var divider := int(config["distant_rate_divider"])
	var distant := float(config["distant_rate_m"])
	for i in range(agents.size() - 1, -1, -1):
		var a := agents[i]
		if a.state != Pedestrian.State.WALKING:
			_step_struck(a, delta)
			if a.state == Pedestrian.State.DOWN and a.timer <= 0.0 and not a.held:
				_drop(a)
				agents.remove_at(i)
			continue
		var d := _distance_to_anchors(a.position())
		if d > distant:
			if _frame % divider != 0:
				continue
			_step_agent(a, delta * divider)
		else:
			_step_agent(a, delta)


func _step_struck(a: Pedestrian, delta: float) -> void:
	a.timer -= delta
	if a.ragdoll != null:
		a.transform = a.ragdoll.root_transform()
	elif a.body != null:
		a.transform = a.body.global_transform
	if a.state == Pedestrian.State.HIT and a.timer <= 0.0:
		a.state = Pedestrian.State.DOWN
		a.timer = float(config["remove_after_s"])
		if a.ragdoll != null:
			a.ragdoll.settle()
		if a.body != null:
			a.body.make_walker()


func _step_agent(a: Pedestrian, delta: float) -> void:
	var before := a.position()
	_move_agent(a, delta)
	_animate(a, before, delta)


## Advances the walk cycle from how far the agent actually moved (zero while waiting).
func _animate(a: Pedestrian, before: Vector3, delta: float) -> void:
	var moved := Vector2(a.position().x - before.x, a.position().z - before.z).length()
	if moved > 3.0:  # a jump (snapshot reorder, respawn): keep the cycle, not a sprint
		return
	var w := CharacterRig.step_walk(a.walk_phase, a.walk_amount, delta, moved / maxf(delta, 0.0001))
	a.walk_phase = w.x
	a.walk_amount = w.y


func _move_agent(a: Pedestrian, delta: float) -> void:
	var path: WalkGraph.WalkPath = walk.paths[a.path_id]
	var pace := 1.0
	if a.stumble > 0.0:
		# Shoved: facing whoever did it and rocking back, then running (the flee waits).
		a.stumble -= delta
		var to_them := a.stumble_from - a.position()
		to_them.y = 0.0
		if to_them.length_squared() > 0.01:
			var face := Basis.looking_at(to_them.normalized(), Vector3.UP)
			var lean := STUMBLE_LEAN_RAD * minf(a.stumble * 2.0, 1.0)
			a.transform = Transform3D(face * Basis(Vector3.RIGHT, lean), a.position())
		return
	if a.fleeing > 0.0:
		a.fleeing -= delta
		a.startled = 0.0
		# Run whichever way along the path takes them away from the threat.
		var ahead := path.direction_at(a.distance) * (1.0 if a.forward else -1.0)
		var away := a.position() - a.flee_from
		away.y = 0.0
		if away.length_squared() > 0.01 and ahead.dot(away) < 0.0:
			a.forward = not a.forward
		pace = FLEE_SPEED_MPS / maxf(a.speed, 0.1)
	if a.startled > 0.0:
		a.startled -= delta
		var to := a.startle_from - a.position()
		to.y = 0.0
		if to.length_squared() > 0.01:
			a.transform = Transform3D(Basis.looking_at(to.normalized(), Vector3.UP), a.position())
		return
	var dir := path.direction_at(a.distance) * (1.0 if a.forward else -1.0)
	if a.fleeing <= 0.0 and _player_ahead(a, dir):
		a.wait_time += delta
		if a.wait_time < float(config["stop_wait_max_s"]):
			_place(a, path, dir)
			return
		a.forward = not a.forward  # waited long enough: go the other way
		a.wait_time = 0.0
		dir = -dir
	else:
		a.wait_time = 0.0
	a.distance += a.speed * pace * delta * (1.0 if a.forward else -1.0)
	if a.distance >= path.length or a.distance <= 0.0:
		_turn_at_end(a, path)
		path = walk.paths[a.path_id]
		dir = path.direction_at(a.distance) * (1.0 if a.forward else -1.0)
	_place(a, path, dir)


func _place(a: Pedestrian, path: WalkGraph.WalkPath, dir: Vector3) -> void:
	var pos := path.position_at(a.distance)
	var left := Vector3(dir.z, 0.0, -dir.x)
	var margin := float(config["edge_margin_m"])
	var half := maxf(path.width_m * 0.5 - margin, 0.0)
	pos += left * clampf(a.lateral, -half, half)
	a.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)


## Picks a connected path at the end just reached, preferring to keep heading; reverses at dead ends.
func _turn_at_end(a: Pedestrian, path: WalkGraph.WalkPath) -> void:
	var at_end := a.forward
	var options := walk.connections(path, at_end)
	var key := path.end_key if at_end else path.start_key
	var heading := path.direction_at(path.length if at_end else 0.0) * (1.0 if at_end else -1.0)
	if options.is_empty():
		a.forward = not a.forward
		a.distance = clampf(a.distance, 0.0, path.length)
		return
	# Weighted by how well each option continues the heading; a straight continuation wins most often.
	var weights: Array[float] = []
	var total := 0.0
	for pid in options:
		var other: WalkGraph.WalkPath = walk.paths[pid]
		var starts := walk.enters_at_start(other, key)
		var out_dir := other.direction_at(0.0) if starts else -other.direction_at(other.length)
		var w := 0.2 + maxf(heading.dot(out_dir), 0.0) * 2.0
		w *= float((config.get("turn_bias", {}) as Dictionary).get(other.kind, 1.0))  # cycle lanes are for bikes
		weights.append(w)
		total += w
	var r := rng.randf() * total
	var chosen: int = options[options.size() - 1]
	for i in range(options.size()):
		r -= weights[i]
		if r <= 0.0:
			chosen = options[i]
			break
	var next: WalkGraph.WalkPath = walk.paths[chosen]
	if next.kind == "crossing" and not crossing_open(next):
		# Wait at the kerb: stay on this path's end and try again next tick (after a long wait,
		# cross anyway: a stuck light or an endless stream of cars should not strand anyone).
		a.kerb_wait += 1.0 / 60.0
		if a.kerb_wait < float(config.get("kerb_wait_max_s", 30.0)):
			a.distance = clampf(a.distance, 0.0, path.length)
			a.waiting_to_cross = true
			return
	a.kerb_wait = 0.0
	a.waiting_to_cross = false
	a.path_id = chosen
	a.forward = walk.enters_at_start(next, key)
	a.distance = 0.0 if a.forward else next.length


func _player_ahead(a: Pedestrian, dir: Vector3) -> bool:
	var reach := float(config["stop_for_player_m"])
	var pos := a.position()
	for o in obstacles:
		if o == null or not is_instance_valid(o):
			continue
		var rel := o.global_position - pos
		rel.y = 0.0
		var along := rel.dot(dir)
		if along <= 0.0 or along > reach:
			continue
		var side := (rel - dir * along).length()
		if side < 0.9:
			return true
	return false


func _distance_to_anchors(p: Vector3) -> float:
	var best := INF
	for anchor in anchors:
		best = minf(best, Vector2(p.x - anchor.x, p.z - anchor.z).length())
	return best


func _despawn_far() -> void:
	var far := float(config["despawn_radius_m"])
	for i in range(agents.size() - 1, -1, -1):
		var a := agents[i]
		if a.held:
			continue  # an ambulance is on its way; it takes them away itself
		if _distance_to_anchors(a.position()) > far:
			_drop(a)
			agents.remove_at(i)


func _spawn_one() -> void:
	var anchor := anchors[rng.randi_range(0, anchors.size() - 1)]
	var candidates := walk.paths_near(anchor, float(config["spawn_radius_m"]))
	if candidates.is_empty():
		return
	var weights: Dictionary = config["kind_weights"]
	var total := 0.0
	for p in candidates:
		total += float(weights.get(p.kind, 0.3))
	if total <= 0.0:
		return
	var r := rng.randf() * total
	var chosen: WalkGraph.WalkPath = candidates[candidates.size() - 1]
	for p in candidates:
		r -= float(weights.get(p.kind, 0.3))
		if r <= 0.0:
			chosen = p
			break
	var d := rng.randf() * chosen.length
	var pos := chosen.position_at(d)
	if _distance_to_anchors(pos) < float(config["min_spawn_distance_m"]):
		return
	var a := Pedestrian.new()
	var colors: Array = config["colors"]
	var c: Array = colors[rng.randi_range(0, colors.size() - 1)]
	a.color = Color(float(c[0]), float(c[1]), float(c[2]))
	a.path_id = chosen.id
	a.distance = d
	a.forward = rng.randf() < 0.5
	a.speed = rng.randf_range(float(config["walk_speed_min_mps"]), float(config["walk_speed_max_mps"]))
	a.lateral = rng.randf_range(-1.0, 1.0) * chosen.width_m * 0.5
	_place(a, chosen, chosen.direction_at(d) * (1.0 if a.forward else -1.0))
	agents.append(a)


## Host: packs the people within `radius` of `around` as x, y, z, yaw, colour index per agent.
func snapshot(around: Vector3, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var colors: Array = config["colors"]
	for a in agents:
		var p := a.position()
		if Vector2(p.x - around.x, p.z - around.z).length() > radius:
			continue
		var fwd := -a.transform.basis.z
		out.append(p.x)
		out.append(p.y)
		out.append(p.z)
		out.append(atan2(fwd.x, fwd.z))
		out.append(float(TrafficManager._color_index(colors, a.color)))
	return out


## Client: replaces the people with the host's snapshot (see `snapshot`).
func apply_snapshot(data: PackedFloat32Array) -> void:
	var n := data.size() / 5
	var colors: Array = config["colors"]
	while agents.size() > n:
		_drop(agents[agents.size() - 1])
		agents.pop_back()
	while agents.size() < n:
		agents.append(Pedestrian.new())
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_snapshot_ms) / 1000.0, 0.001, 1.0)
	_last_snapshot_ms = now
	for i in range(n):
		var a := agents[i]
		var k := i * 5
		var yaw := data[k + 3]
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		var before := a.position()
		a.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(data[k], data[k + 1], data[k + 2]))
		var moved := Vector2(a.position().x - before.x, a.position().z - before.z).length()
		a.speed = moved / dt if moved < 3.0 else a.speed  # walking pace between snapshots, for the walk cycle
		var ci := int(data[k + 4])
		if ci >= 0 and ci < colors.size():
			var c: Array = colors[ci]
			a.color = Color(float(c[0]), float(c[1]), float(c[2]))


## Gives physics bodies to the agents nearest the anchors, takes them from the rest.
func _assign_bodies() -> void:
	if _bodies.is_empty():
		return
	var radius := float(config["body_radius_m"])
	var near: Array[Pedestrian] = []
	for a in agents:
		if a.state != Pedestrian.State.WALKING and a.body != null:
			if a.state == Pedestrian.State.DOWN and _distance_to_anchors(a.position()) > radius:
				_release_body(a)
			continue
		if _distance_to_anchors(a.position()) <= radius:
			near.append(a)
	near.sort_custom(func(x: Pedestrian, y: Pedestrian) -> bool: return _distance_to_anchors(x.position()) < _distance_to_anchors(y.position()))
	var wanted := {}
	for i in range(mini(near.size(), _bodies.size())):
		wanted[near[i]] = true
	for a in agents:
		if a.body != null and not wanted.has(a) and a.state == Pedestrian.State.WALKING:
			_release_body(a)
	for a in wanted:
		if a.body == null:
			var body := _free_body()
			if body == null:
				break
			a.body = body
			body.agent = a
			body.process_mode = Node.PROCESS_MODE_INHERIT
			body.freeze = true
	for a in agents:
		if a.body != null and a.state == Pedestrian.State.WALKING:
			a.body.global_transform = a.transform


func _free_body() -> PedestrianBody:
	for b in _bodies:
		if b.agent == null:
			return b
	return null


func _release_body(a: Pedestrian) -> void:
	if a.body == null:
		return
	a.body.agent = null
	a.body.make_walker()
	a.body.global_position = Vector3(0, -1000, 0)
	# Deferred: this can run inside a physics callback (a knock-down from the sensor).
	a.body.park.call_deferred()
	a.body = null


## A vehicle closing on a walker's sensor: the person is thrown with most of the vehicle's
## velocity and a little lift, and the player's car feels a configured knock back.
func _on_body_hit(body: PedestrianBody, vehicle: Node3D, velocity: Vector3) -> void:
	var a := body.agent
	if a == null or a.state != Pedestrian.State.WALKING:
		return
	var mass := float(config.get("mass_kg", 75.0))
	var throw := velocity * float(config.get("hit_transfer", 0.9)) + Vector3.UP * float(config.get("hit_lift_mps", 1.5))
	knock_down(a, throw * mass, a.position() + Vector3.UP * 0.5)
	struck_by_vehicle.emit(a, vehicle)
	if vehicle is VehicleBody3D and velocity.length() > 0.01:
		(vehicle as VehicleBody3D).apply_central_impulse(-velocity.normalized() * float(config.get("hit_car_impulse_ns", 2000.0)))


## How fast a knocked-down person's body is moving (zero while walking or without a body).
func thrown_velocity(a: Pedestrian) -> Vector3:
	if a.state == Pedestrian.State.WALKING:
		return Vector3.ZERO
	if a.ragdoll != null:
		return Vector3.ZERO if a.ragdoll.is_settled() else a.ragdoll.velocity()
	if a.body == null or a.body.freeze:
		return Vector3.ZERO
	return a.body.linear_velocity


## Knocks a walking pedestrian down: `impulse` (N s) applied at world `point`. The one entry
## point for anything that floors someone (vehicles now; later weapons and the like). The
## person falls as a ragdoll from the pool, `spread` (0..1, default from the config) of the
## impulse moving the whole body and the rest the bone nearest `point`; without a ragdoll the
## walking capsule tumbles instead.
func knock_down(a: Pedestrian, impulse: Vector3, point: Vector3, spread: float = -1.0) -> void:
	if a.state != Pedestrian.State.WALKING:
		return
	a.state = Pedestrian.State.HIT
	a.timer = float(config["hit_physics_s"])
	var rd := _take_ragdoll()
	if rd != null:
		_release_body(a)
		a.ragdoll = rd
		rd.begin(pool_profiles[_pool_of(a)], a.transform, a.walk_phase, a.walk_amount)
		rd.apply_impulse(impulse, point, float(config.get("hit_spread", 0.7)) if spread < 0.0 else spread)
	elif a.body != null:
		a.body.make_dynamic(Vector3.ZERO)
		a.body.apply_impulse(impulse, point - a.body.global_position)
	downed.emit(a)


## Stands a downed person back up where they lie and sends them on their way along their
## path (an ambulance in the clean tone).
func revive(a: Pedestrian) -> void:
	if a.state == Pedestrian.State.WALKING or not agents.has(a):
		return
	var at := a.position()
	_drop(a)
	a.state = Pedestrian.State.WALKING
	a.timer = 0.0
	a.held = false
	a.wait_time = 0.0
	if walk != null and a.path_id >= 0 and a.path_id < walk.paths.size():
		var path := walk.paths[a.path_id]
		a.distance = closest_distance(path, at)
		_place(a, path, path.direction_at(a.distance) * (1.0 if a.forward else -1.0))


## Takes a downed person out of the world (carried off on a stretcher, lifted by a drone).
func carry_off(a: Pedestrian) -> void:
	if not agents.has(a):
		return
	_drop(a)
	agents.erase(a)


## Distance along `path` of the point on it nearest `p`.
static func closest_distance(path: WalkGraph.WalkPath, p: Vector3) -> float:
	var best := 0.0
	var best_d := INF
	for i in range(path.points.size() - 1):
		var a := path.points[i]
		var seg := path.points[i + 1] - a
		var len2 := seg.length_squared()
		var t := clampf((p - a).dot(seg) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
		var d := p.distance_to(a + seg * t)
		if d < best_d:
			best_d = d
			best = path.cumulative[i] + t * sqrt(len2)
	return best


## Knocks down the walking pedestrian nearest `around` within `radius`, pushed with `impulse`
## at chest height (benchmarks and debug). Returns false when nobody is in reach.
## A horn or a shout at `point`: walkers within `radius` stop and turn to look for `seconds`.
## Returns how many did.
func startle(point: Vector3, radius: float, seconds: float = STARTLE_S) -> int:
	var n := 0
	for a in agents:
		if a.state == Pedestrian.State.WALKING and a.position().distance_to(point) <= radius:
			a.startled = seconds * randf_range(0.8, 1.2)
			a.startle_from = point
			n += 1
	return n


## A non-lethal hit (paint): the walker gets splotches of palette colour `palette_index` and
## runs off from `from`.
func paint(a: Pedestrian, palette_index: int, from: Vector3, seconds: float = FLEE_S) -> void:
	if a.state != Pedestrian.State.WALKING:
		return
	a.paint_index = palette_index + 1
	a.paint_amount = minf(a.paint_amount + 0.45, 0.95)
	a.fleeing = seconds
	a.flee_from = from


## A shove (fists where nobody goes down): the walker stumbles back from `from` for
## `stumble_s`, then runs off for `seconds`.
func shove(a: Pedestrian, from: Vector3, stumble_s: float, seconds: float = FLEE_S) -> void:
	if a.state != Pedestrian.State.WALKING:
		return
	a.stumble = stumble_s
	a.stumble_from = from
	a.startled = 0.0
	a.fleeing = seconds
	a.flee_from = from


## Gunfire at `point`: walkers within `radius` run away from it for `seconds`. Returns how many.
func flee(point: Vector3, radius: float, seconds: float = FLEE_S) -> int:
	var n := 0
	for a in agents:
		if a.state == Pedestrian.State.WALKING and a.position().distance_to(point) <= radius:
			a.fleeing = seconds * randf_range(0.8, 1.2)
			a.flee_from = point
			n += 1
	return n


## The walker behind a physics body, or null (weapons hit bodies).
func agent_of(body: Node) -> Pedestrian:
	if body is PedestrianBody:
		return (body as PedestrianBody).agent
	return null


func knock_down_nearest(around: Vector3, radius: float, impulse: Vector3) -> bool:
	var best: Pedestrian = null
	var best_d := radius
	for a in agents:
		var d := a.position().distance_to(around)
		if a.state == Pedestrian.State.WALKING and d < best_d:
			best_d = d
			best = a
	if best == null:
		return false
	knock_down(best, impulse, best.position() + Vector3.UP * 1.1)
	return true


## Ragdolls currently simulating (not yet settled).
func falling_count() -> int:
	var n := 0
	for rd in _ragdolls:
		if rd.active and not rd.is_settled():
			n += 1
	return n


## A free ragdoll, or the one under the downed person with the least time left (who goes).
func _take_ragdoll() -> CharacterRagdoll:
	if _ragdolls.is_empty() or pool_profiles.is_empty():
		return null
	for rd in _ragdolls:
		if not rd.active:
			return rd
	var oldest: Pedestrian = null
	for a in agents:
		if a.ragdoll != null and a.state == Pedestrian.State.DOWN and not a.held and (oldest == null or a.timer < oldest.timer):
			oldest = a
	if oldest == null:
		return null  # every ragdoll is mid-fall: this one tumbles as a capsule
	var rd := oldest.ragdoll
	_drop(oldest)
	agents.erase(oldest)
	return rd


func _pool_of(a: Pedestrian) -> int:
	if a.pool < 0:
		a.pool = int(a.color.r * 255.0 + a.color.g * 255.0 * 3.0 + a.color.b * 255.0 * 7.0) % POOLS
	return a.pool


## Lets go of everything an agent holds (body, ragdoll) before it is removed.
func _drop(a: Pedestrian) -> void:
	_release_body(a)
	if a.ragdoll != null:
		a.ragdoll.release()
		a.ragdoll = null


## Removes every agent (co-op clients switching to the host's people).
func clear_agents() -> void:
	for a in agents:
		_drop(a)
	agents.clear()


## The walk shader's per-instance data for an agent: phase, amount (zero unless walking).
static func walk_custom(a: Pedestrian) -> Color:
	var walking := a.state == Pedestrian.State.WALKING
	return Color(a.walk_phase, a.walk_amount if walking else 0.0, float(a.paint_index), a.paint_amount)


func _render() -> void:
	if _pools.is_empty():
		return
	var counts := PackedInt32Array()
	counts.resize(POOLS)
	for a in agents:
		if a.ragdoll != null:
			continue  # drawn by its ragdoll
		var mm := _pools[_pool_of(a)].multimesh
		var k := counts[a.pool]
		if k >= mm.instance_count:
			continue
		mm.set_instance_transform(k, a.transform)
		mm.set_instance_custom_data(k, walk_custom(a))
		counts[a.pool] = k + 1
	for i in range(POOLS):
		_pools[i].multimesh.visible_instance_count = counts[i]
