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

const BODY_SCENE := preload("res://world/pedestrians/pedestrian_body.tscn")
const CONFIG_PATH := "res://world/pedestrians/pedestrian_config.json"

var config: Dictionary = {}
var walk: WalkGraph
var max_agents: int = 120
var agents: Array[Pedestrian] = []
var rng := RandomNumberGenerator.new()
var enabled: bool = true
## Positions pedestrians are kept around (the players). Set each frame by the scene.
var anchors: PackedVector3Array = PackedVector3Array()
## Player bodies pedestrians stop for. Set each frame by the scene.
var obstacles: Array[Node3D] = []
var _spawn_timer: float = 0.0
var _frame: int = 0
var _multimesh: MultiMeshInstance3D
var _bodies: Array[PedestrianBody] = []


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


func setup(walk_graph: WalkGraph) -> void:
	walk = walk_graph
	_setup_rendering()


func _setup_rendering() -> void:
	if _multimesh != null:
		return
	_multimesh = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var capsule := CapsuleMesh.new()
	capsule.radius = float(config["radius_m"])
	capsule.height = float(config["height_m"])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.7
	capsule.material = mat
	mm.mesh = capsule
	mm.instance_count = max_agents
	mm.visible_instance_count = 0
	_multimesh.multimesh = mm
	add_child(_multimesh)
	for i in range(int(config["body_pool"])):
		var body: PedestrianBody = BODY_SCENE.instantiate()
		body.hit.connect(_on_body_hit)
		add_child(body)
		body.process_mode = Node.PROCESS_MODE_DISABLED
		body.global_position = Vector3(0, -1000, 0)
		_bodies.append(body)


func active_count() -> int:
	return agents.size()


func _physics_process(delta: float) -> void:
	if walk == null or not enabled or anchors.is_empty():
		return
	_frame += 1
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = float(config["spawn_interval_s"])
		_despawn_far()
		for i in range(int(config["spawns_per_interval"])):
			if agents.size() >= max_agents:
				break
			_spawn_one()
	step(delta)
	_assign_bodies()
	_render()


## Advances every agent. Pure of spawning and rendering so tests can drive it directly.
func step(delta: float) -> void:
	var divider := int(config["distant_rate_divider"])
	var distant := float(config["distant_rate_m"])
	for i in range(agents.size() - 1, -1, -1):
		var a := agents[i]
		if a.state != Pedestrian.State.WALKING:
			_step_struck(a, delta)
			if a.state == Pedestrian.State.DOWN and a.timer <= 0.0:
				_release_body(a)
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
	if a.body != null:
		a.transform = a.body.global_transform
	if a.state == Pedestrian.State.HIT and a.timer <= 0.0:
		a.state = Pedestrian.State.DOWN
		a.timer = float(config["remove_after_s"])
		if a.body != null:
			a.body.freeze = true
			a.body.linear_velocity = Vector3.ZERO
			a.body.angular_velocity = Vector3.ZERO


func _step_agent(a: Pedestrian, delta: float) -> void:
	var path: WalkGraph.WalkPath = walk.paths[a.path_id]
	var dir := path.direction_at(a.distance) * (1.0 if a.forward else -1.0)
	if _player_ahead(a, dir):
		a.wait_time += delta
		if a.wait_time < float(config["stop_wait_max_s"]):
			_place(a, path, dir)
			return
		a.forward = not a.forward  # waited long enough: go the other way
		a.wait_time = 0.0
		dir = -dir
	else:
		a.wait_time = 0.0
	a.distance += a.speed * delta * (1.0 if a.forward else -1.0)
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
		if _distance_to_anchors(a.position()) > far:
			_release_body(a)
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
	a.body.freeze = true
	a.body.linear_velocity = Vector3.ZERO
	a.body.process_mode = Node.PROCESS_MODE_DISABLED
	a.body.global_position = Vector3(0, -1000, 0)
	a.body = null


func _on_body_hit(body: PedestrianBody) -> void:
	var a := body.agent
	if a == null or a.state != Pedestrian.State.WALKING:
		return
	a.state = Pedestrian.State.HIT
	a.timer = float(config["hit_physics_s"])
	body.freeze = false


func _render() -> void:
	if _multimesh == null:
		return
	var mm := _multimesh.multimesh
	var n := mini(agents.size(), mm.instance_count)
	mm.visible_instance_count = n
	var lift := float(config["height_m"]) * 0.5
	for i in range(n):
		var a := agents[i]
		mm.set_instance_transform(i, a.transform.translated_local(Vector3(0.0, lift, 0.0)))
		mm.set_instance_color(i, a.color)
