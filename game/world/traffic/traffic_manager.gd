class_name TrafficManager
extends Node3D
## Spawns and drives traffic agents on a LaneGraph around the players.
##
## Agents are plain data (TrafficAgent). One MultiMesh draws them all; a small
## pool of physics bodies follows the agents nearest the players so the player
## can collide with them. Each physics step an agent gets a target speed from
## its lane's limit, the car ahead (headway rule), and junction priority (claim
## within stopping distance, first claim goes first, waiting cars give up after
## a while). Agents beyond `distant_rate_m` from every player step every Nth
## frame with a larger delta. With co-op the host runs this and sends transforms.

const CAR_SCENE := preload("res://world/traffic/traffic_car.tscn")
const DRIVABLE_CAR_SCENE := preload("res://actors/vehicles/placeholder_car.tscn")
const CONFIG_PATH := "res://world/traffic/traffic_config.json"
const BODY_POOL := 24
const BODY_RADIUS_M := 70.0

var config: Dictionary = {}
var lanes: LaneGraph
var max_agents: int = 150
var agents: Array[TrafficAgent] = []
var rng := RandomNumberGenerator.new()
var enabled: bool = true
## Positions traffic is kept around (the players). Set each frame by the scene.
var anchors: PackedVector3Array = PackedVector3Array()
## Player bodies (vehicles or people) that traffic keeps headway from. Set each frame by the scene.
var obstacles: Array[Node3D] = []
var _agents_by_path: Dictionary = {}
var _junction_occupants: Dictionary = {}
var _spawn_timer: float = 0.0
var _frame: int = 0
var _debug_mesh: MeshInstance3D
var _multimesh: MultiMeshInstance3D
var _bodies: Array[TrafficCar] = []
var _lane_cells: Dictionary = {}  # Vector2i (64 m cells) -> Array[int] lane path ids
const CELL_M := 64.0


func _ready() -> void:
	if config.is_empty():
		load_config()
	rng.seed = 430


## Loads traffic_config.json. Returns false and logs when unreadable.
func load_config(path: String = CONFIG_PATH) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TrafficManager: cannot read %s" % path)
		return false
	config = parsed
	max_agents = int(config["max_agents"])
	return true


func setup(lane_graph: LaneGraph) -> void:
	lanes = lane_graph
	_lane_cells.clear()
	for lp in lanes.paths:
		if lp.is_connector or lp.points.is_empty():
			continue
		var mid := lp.position_at(lp.length * 0.5)
		var key := Vector2i(int(floor(mid.x / CELL_M)), int(floor(mid.z / CELL_M)))
		if not _lane_cells.has(key):
			_lane_cells[key] = []
		_lane_cells[key].append(lp.id)
	_setup_rendering()


func _setup_rendering() -> void:
	if _multimesh != null:
		return
	_multimesh = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(float(config["car_width_m"]), 1.3, float(config["car_length_m"]))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.45
	mat.metallic = 0.3
	box.material = mat
	mm.mesh = box
	mm.instance_count = max_agents
	mm.visible_instance_count = 0
	_multimesh.multimesh = mm
	add_child(_multimesh)
	for i in range(BODY_POOL):
		var body: TrafficCar = CAR_SCENE.instantiate()
		body.hit.connect(_on_body_hit)
		add_child(body)
		body.process_mode = Node.PROCESS_MODE_DISABLED
		body.global_position = Vector3(0, -1000, 0)
		_bodies.append(body)


func active_count() -> int:
	return agents.size()


func _physics_process(delta: float) -> void:
	if lanes == null or not enabled or anchors.is_empty():
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
	_rebuild_lane_index()
	var divider := int(config["distant_rate_divider"])
	var distant := float(config["distant_rate_m"])
	for a in agents:
		if a.retired:
			_step_retired(a, delta)
			continue
		var d := _distance_to_anchors(a.position())
		if d > distant:
			if _frame % divider != 0:
				continue
			_step_agent(a, delta * divider)
		else:
			_step_agent(a, delta)


## Hit cars run physics for the hit window, then either rejoin a lane or rest where they are.
func _step_retired(a: TrafficAgent, delta: float) -> void:
	if a.resting:
		return
	a.hit_timer -= delta
	if a.body != null:
		a.transform = a.body.global_transform
	if a.hit_timer > 0.0:
		return
	if a.body != null and not a.body.freeze:
		a.body.freeze = true
		a.body.linear_velocity = Vector3.ZERO
		a.body.angular_velocity = Vector3.ZERO
	if not _try_recover(a):
		a.resting = true
		_leave_junction(a)
		_project_onto_lane(a, float(config["parked_block_reach_m"]))


## Puts a hit car back on the nearest lane when it is close and facing along it.
func _try_recover(a: TrafficAgent) -> bool:
	var reach := float(config["recover_reach_m"])
	if not _project_onto_lane(a, reach):
		return false
	var path: LaneGraph.LanePath = lanes.paths[a.path_id]
	var forward := -a.transform.basis.z
	if forward.dot(path.direction_at(a.distance)) < float(config["recover_align_min"]):
		return false
	a.retired = false
	a.resting = false
	a.speed = 0.0
	a.wait_time = 0.0
	_leave_junction(a)
	a.transform = Transform3D(Basis.looking_at(path.direction_at(a.distance), Vector3.UP), path.position_at(a.distance))
	return true


## Sets path_id and distance to the nearest lane within reach. False when none is that close.
func _project_onto_lane(a: TrafficAgent, reach: float) -> bool:
	var pos := a.position()
	var best_d := reach
	var found := false
	for lp in lanes_near(pos, reach + 120.0):
		var c := lp.closest(pos)
		if c.y < best_d:
			best_d = c.y
			a.path_id = lp.id
			a.distance = c.x
			found = true
	return found


func _rebuild_lane_index() -> void:
	_agents_by_path.clear()
	for a in agents:
		if a.retired and not a.resting:
			continue  # still tumbling; nobody can plan around it yet
		if not _agents_by_path.has(a.path_id):
			_agents_by_path[a.path_id] = []
		_agents_by_path[a.path_id].append(a)
	for key in _agents_by_path:
		var list: Array = _agents_by_path[key]
		if list.size() > 1:
			list.sort_custom(func(x: TrafficAgent, y: TrafficAgent) -> bool: return x.distance < y.distance)


func _step_agent(a: TrafficAgent, delta: float) -> void:
	var path: LaneGraph.LanePath = lanes.paths[a.path_id]
	var limit := float(path.speed_kph) / 3.6 * float(config["speed_fraction"])
	if path.is_connector:
		limit = minf(limit, float(config["connector_speed_kph"]) / 3.6)
	var target := limit
	var gap := _gap_ahead(a, path)
	var min_gap := float(config["min_gap_m"])
	var desired := min_gap + a.speed * float(config["time_headway_s"])
	if gap < desired:
		target = minf(target, maxf(0.0, a.speed * (gap - min_gap) / maxf(desired - min_gap, 0.1)))
	var remaining := path.length - a.distance
	var decel := float(config["decel_mps2"])
	var stop_dist := a.speed * a.speed / (2.0 * decel) + 3.0
	if not path.is_connector and remaining < stop_dist and not path.next.is_empty():
		var nxt: LaneGraph.LanePath = lanes.paths[path.next[0]]
		if nxt.junction_node != "" and a.occupies_junction != nxt.junction_node:
			if _junction_busy(nxt.junction_node, a):
				a.wait_time += delta
				if a.wait_time < float(config["yield_wait_max_s"]):
					target = 0.0
				else:
					_claim_junction(a, nxt.junction_node)
			else:
				_claim_junction(a, nxt.junction_node)
	if target > a.speed:
		a.speed = minf(a.speed + float(config["accel_mps2"]) * delta, target)
	else:
		a.speed = maxf(a.speed - decel * delta, target)
	a.distance += a.speed * delta
	while a.distance >= path.length:
		var next_id := lanes.choose_next(path, rng)
		if next_id < 0:
			a.distance = path.length
			a.speed = 0.0
			break
		a.distance -= path.length
		if path.is_connector:
			_leave_junction(a)
		path = lanes.paths[next_id]
		a.path_id = next_id
		if path.junction_node != "":
			_claim_junction(a, path.junction_node)
			a.wait_time = 0.0
	var pos := path.position_at(a.distance)
	var dir := path.direction_at(a.distance)
	a.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)


func _claim_junction(a: TrafficAgent, node: String) -> void:
	if a.occupies_junction == node:
		return
	_leave_junction(a)
	a.occupies_junction = node
	if not _junction_occupants.has(node):
		_junction_occupants[node] = []
	_junction_occupants[node].append(a)


func _leave_junction(a: TrafficAgent) -> void:
	if a.occupies_junction != "":
		var list: Array = _junction_occupants.get(a.occupies_junction, [])
		list.erase(a)
		a.occupies_junction = ""


func _junction_busy(node: String, me: TrafficAgent) -> bool:
	for o in _junction_occupants.get(node, []):
		if o != me and not o.retired:
			return true
	return false


func _gap_ahead(a: TrafficAgent, path: LaneGraph.LanePath) -> float:
	var car_len := float(config["car_length_m"])
	var best := _obstacle_gap(a, path)
	for o in _agents_by_path.get(a.path_id, []):
		if o != a and o.distance > a.distance:
			best = minf(best, o.distance - a.distance - car_len)
			break
	if best == INF and not path.next.is_empty():
		var remaining := path.length - a.distance
		if remaining < float(config["lookahead_m"]):
			for nid in path.next:
				for o in _agents_by_path.get(nid, []):
					best = minf(best, remaining + o.distance - car_len)
					break
	return best


## Gap to the nearest player body ahead in this lane's corridor, or INF.
func _obstacle_gap(a: TrafficAgent, path: LaneGraph.LanePath) -> float:
	if obstacles.is_empty():
		return INF
	var car_len := float(config["car_length_m"])
	var corridor := float(config["car_width_m"]) * 0.5
	var lookahead := float(config["lookahead_m"])
	var pos := a.position()
	var best := INF
	for o in obstacles:
		if o == null or not is_instance_valid(o):
			continue
		var radius := _obstacle_radius(o)
		var rel := o.global_position - pos
		var flat := Vector2(rel.x, rel.z).length()
		if flat > lookahead + radius or absf(rel.y) > 3.0:
			continue
		var c := path.closest(o.global_position)
		var along := c.x - a.distance
		if along <= 0.0 or c.y > corridor + radius:
			continue
		best = minf(best, along - car_len * 0.5 - radius)
	return best


func _obstacle_radius(o: Node3D) -> float:
	if o is VehicleBody3D:
		return float(config["car_length_m"]) * 0.5
	return float(config["person_radius_m"])


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
			_leave_junction(a)
			_release_body(a)
			agents.remove_at(i)


## Lane paths within radius of a position, via the cell index.
func lanes_near(position: Vector3, radius: float) -> Array[LaneGraph.LanePath]:
	var out: Array[LaneGraph.LanePath] = []
	var cells := int(ceil(radius / CELL_M))
	var cx := int(floor(position.x / CELL_M))
	var cz := int(floor(position.z / CELL_M))
	for dx in range(-cells, cells + 1):
		for dz in range(-cells, cells + 1):
			for pid in _lane_cells.get(Vector2i(cx + dx, cz + dz), []):
				var lp: LaneGraph.LanePath = lanes.paths[pid]
				var mid := lp.position_at(lp.length * 0.5)
				if Vector2(mid.x - position.x, mid.z - position.z).length() <= radius:
					out.append(lp)
	return out


func _spawn_one() -> void:
	var anchor := anchors[rng.randi_range(0, anchors.size() - 1)]
	var candidates := lanes_near(anchor, float(config["spawn_radius_m"]))
	if candidates.is_empty():
		return
	var weights: Dictionary = config["class_weights"]
	var total := 0.0
	for lp in candidates:
		total += float(weights.get(lp.road_class, 0.5))
	var r := rng.randf() * total
	var chosen: LaneGraph.LanePath = candidates[candidates.size() - 1]
	for lp in candidates:
		r -= float(weights.get(lp.road_class, 0.5))
		if r <= 0.0:
			chosen = lp
			break
	var d := rng.randf() * chosen.length
	var pos := chosen.position_at(d)
	if _distance_to_anchors(pos) < float(config["min_spawn_distance_m"]):
		return
	if not _lane_gap_clear(chosen.id, d):
		return
	var a := TrafficAgent.new()
	var colors: Array = config["colors"]
	var c: Array = colors[rng.randi_range(0, colors.size() - 1)]
	a.color = Color(float(c[0]), float(c[1]), float(c[2]))
	a.path_id = chosen.id
	a.distance = d
	a.speed = float(chosen.speed_kph) / 3.6 * 0.5
	a.transform = Transform3D(Basis.looking_at(chosen.direction_at(d), Vector3.UP), pos)
	agents.append(a)


func _lane_gap_clear(path_id: int, d: float) -> bool:
	var need := float(config["car_length_m"]) + float(config["min_gap_m"])
	for a in agents:
		if a.path_id == path_id and absf(a.distance - d) < need * 2.0:
			return false
	return true


## Gives physics bodies to the agents nearest the anchors, takes them from the rest.
func _assign_bodies() -> void:
	if _bodies.is_empty():
		return
	var near: Array[TrafficAgent] = []
	for a in agents:
		if a.retired and a.body != null:
			if a.resting and _distance_to_anchors(a.position()) > BODY_RADIUS_M:
				_release_body(a)  # at rest and nobody near: the pool gets it back
			continue  # otherwise a hit car keeps its body
		if _distance_to_anchors(a.position()) <= BODY_RADIUS_M:
			near.append(a)
	near.sort_custom(func(x: TrafficAgent, y: TrafficAgent) -> bool: return _distance_to_anchors(x.position()) < _distance_to_anchors(y.position()))
	var wanted := {}
	for i in range(mini(near.size(), BODY_POOL)):
		wanted[near[i]] = true
	for a in agents:
		if a.body != null and not wanted.has(a) and not a.retired:
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
		if a.body != null and not a.retired:
			a.body.global_transform = a.transform.translated_local(Vector3.ZERO)


func _free_body() -> TrafficCar:
	for b in _bodies:
		if b.agent == null:
			return b
	return null


func _release_body(a: TrafficAgent) -> void:
	if a.body == null:
		return
	a.body.agent = null
	a.body.freeze = true
	a.body.linear_velocity = Vector3.ZERO
	a.body.process_mode = Node.PROCESS_MODE_DISABLED
	a.body.global_position = Vector3(0, -1000, 0)
	a.body = null


## Replaces the agent behind `body` with a drivable car in its colour at its position.
## Returns null when the body has no agent. The car is added under this manager's parent.
func take_car(body: TrafficCar) -> VehicleBody3D:
	var a := body.agent
	if a == null:
		return null
	var car: VehicleBody3D = DRIVABLE_CAR_SCENE.instantiate()
	var mesh := car.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null and mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = (mesh.material_override as StandardMaterial3D).duplicate()
		mat.albedo_color = a.color
		mesh.material_override = mat
	var holder: Node = get_parent() if get_parent() != null else self
	holder.add_child(car)
	car.global_transform = a.transform.translated_local(Vector3(0.0, 0.3, 0.0))
	if car.has_method("set_spawn"):
		car.set_spawn(car.global_transform)
	_leave_junction(a)
	_release_body(a)
	agents.erase(a)
	return car


func _on_body_hit(car: TrafficCar) -> void:
	var a := car.agent
	if a == null or a.retired:
		return
	a.retired = true
	a.resting = false
	a.hit_timer = float(config["hit_physics_s"])
	_leave_junction(a)
	car.freeze = false


func _render() -> void:
	if _multimesh == null:
		return
	var mm := _multimesh.multimesh
	var n := mini(agents.size(), mm.instance_count)
	mm.visible_instance_count = n
	for i in range(n):
		var a := agents[i]
		mm.set_instance_transform(i, a.transform.translated_local(Vector3(0.0, 0.65, 0.0)))
		mm.set_instance_color(i, a.color)


## Draws lane paths (green) and connectors (orange) as lines; toggled by the scene's graph view.
func set_debug_visible(on: bool) -> void:
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for lp in lanes.paths:
			im.surface_set_color(Color(1.0, 0.6, 0.2) if lp.is_connector else Color(0.3, 1.0, 0.4))
			for i in range(lp.points.size() - 1):
				im.surface_add_vertex(lp.points[i] + Vector3.UP * 0.4)
				im.surface_add_vertex(lp.points[i + 1] + Vector3.UP * 0.4)
		im.surface_end()
		_debug_mesh.mesh = im
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.no_depth_test = true
		_debug_mesh.material_override = m
		add_child(_debug_mesh)
	_debug_mesh.visible = on
