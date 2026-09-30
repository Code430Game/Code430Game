class_name TrafficManager
extends Node3D
## Spawns and drives traffic agents on a LaneGraph around the players.
##
## Each physics step, every agent gets a target speed from its lane's limit,
## the car ahead in its lane (a simple headway rule), and junction priority
## (first into the junction goes first; a waiting car gives up after a while
## to break deadlocks). Agents beyond `distant_rate_m` from every player are
## stepped every Nth frame with a larger delta. The manager owns all agents;
## with co-op the host runs it and clients receive transforms.

const CAR_SCENE := preload("res://world/traffic/traffic_car.tscn")
const CONFIG_PATH := "res://world/traffic/traffic_config.json"

var config: Dictionary = {}
var lanes: LaneGraph
var max_agents: int = 150
var agents: Array[TrafficCar] = []
var rng := RandomNumberGenerator.new()
var enabled: bool = true
## Positions of players (or any anchors) traffic is kept around. Set each frame by the scene.
var anchors: PackedVector3Array = PackedVector3Array()
var _agents_by_path: Dictionary = {}  # path id -> Array[TrafficCar], sorted by distance each step
var _junction_occupants: Dictionary = {}  # node id -> Array[TrafficCar]
var _spawn_timer: float = 0.0
var _frame: int = 0
var _debug_mesh: MeshInstance3D


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


## Advances every agent. Pure of spawning so tests can drive it directly.
func step(delta: float) -> void:
	_rebuild_lane_index()
	var divider := int(config["distant_rate_divider"])
	var distant := float(config["distant_rate_m"])
	for a in agents:
		if a.retired:
			a.hit_timer -= delta
			if a.hit_timer <= 0.0 and not a.freeze:
				a.freeze = true
				a.linear_velocity = Vector3.ZERO
			continue
		var d := _distance_to_anchors(a.global_position)
		if d > distant:
			if _frame % divider != 0:
				continue
			_step_agent(a, delta * divider)
		else:
			_step_agent(a, delta)


func _rebuild_lane_index() -> void:
	_agents_by_path.clear()
	for a in agents:
		if a.retired:
			continue
		if not _agents_by_path.has(a.path_id):
			_agents_by_path[a.path_id] = []
		_agents_by_path[a.path_id].append(a)
	for key in _agents_by_path:
		_agents_by_path[key].sort_custom(func(x: TrafficCar, y: TrafficCar) -> bool: return x.distance < y.distance)


func _step_agent(a: TrafficCar, delta: float) -> void:
	var path: LaneGraph.LanePath = lanes.paths[a.path_id]
	var limit := float(path.speed_kph) / 3.6 * float(config["speed_fraction"])
	if path.is_connector:
		limit = minf(limit, float(config["connector_speed_kph"]) / 3.6)
	var target := limit
	# Car ahead: same path, or the start of the next path.
	var gap := _gap_ahead(a, path)
	var min_gap := float(config["min_gap_m"])
	var desired := min_gap + a.speed * float(config["time_headway_s"])
	if gap < desired:
		target = minf(target, maxf(0.0, a.speed * (gap - min_gap) / maxf(desired - min_gap, 0.1)))
	# Junction priority: within stopping distance of a junction, claim it if free, else wait.
	# The claim is made before entering so two cars cannot both decide to go in the same moment.
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
					_claim_junction(a, nxt.junction_node)  # deadlock breaker: go anyway
			else:
				_claim_junction(a, nxt.junction_node)
	# Speed control.
	if target > a.speed:
		a.speed = minf(a.speed + float(config["accel_mps2"]) * delta, target)
	else:
		a.speed = maxf(a.speed - float(config["decel_mps2"]) * delta, target)
	a.distance += a.speed * delta
	while a.distance >= path.length:
		var next_id := lanes.choose_next(path, rng)
		if next_id < 0:
			a.distance = path.length
			a.speed = 0.0
			break
		a.distance -= path.length
		if path.is_connector:
			_leave_junction(a)  # leaving the junction; a claim made on the approach carries into the connector
		path = lanes.paths[next_id]
		a.path_id = next_id
		if path.junction_node != "":
			_claim_junction(a, path.junction_node)
			a.wait_time = 0.0
	a.place(path.position_at(a.distance), path.direction_at(a.distance))


func _claim_junction(a: TrafficCar, node: String) -> void:
	if a.occupies_junction == node:
		return
	_leave_junction(a)
	a.occupies_junction = node
	if not _junction_occupants.has(node):
		_junction_occupants[node] = []
	_junction_occupants[node].append(a)


func _leave_junction(a: TrafficCar) -> void:
	if a.occupies_junction != "":
		var list: Array = _junction_occupants.get(a.occupies_junction, [])
		list.erase(a)
		a.occupies_junction = ""


func _junction_busy(node: String, me: TrafficCar) -> bool:
	for o in _junction_occupants.get(node, []):
		if o != me and not o.retired:
			return true
	return false


## Distance to the rear of the nearest car ahead on this path (or the start of the next path), or INF.
func _gap_ahead(a: TrafficCar, path: LaneGraph.LanePath) -> float:
	var car_len := float(config["car_length_m"])
	var best := INF
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


func _distance_to_anchors(p: Vector3) -> float:
	var best := INF
	for anchor in anchors:
		best = minf(best, Vector2(p.x - anchor.x, p.z - anchor.z).length())
	return best


func _despawn_far() -> void:
	var far := float(config["despawn_radius_m"])
	for i in range(agents.size() - 1, -1, -1):
		var a := agents[i]
		if _distance_to_anchors(a.global_position) > far:
			_leave_junction(a)
			agents.remove_at(i)
			a.queue_free()


func _spawn_one() -> void:
	var anchor := anchors[rng.randi_range(0, anchors.size() - 1)]
	var candidates := lanes.lanes_near(anchor, float(config["spawn_radius_m"]))
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
	if _lane_gap_clear(chosen.id, d) == false:
		return
	var car: TrafficCar = CAR_SCENE.instantiate()
	var colors: Array = config["colors"]
	var c: Array = colors[rng.randi_range(0, colors.size() - 1)]
	car.tint = Color(float(c[0]), float(c[1]), float(c[2]))
	car.path_id = chosen.id
	car.distance = d
	car.speed = float(chosen.speed_kph) / 3.6 * 0.5
	add_child(car)
	car.place(pos, chosen.direction_at(d))
	agents.append(car)


func _lane_gap_clear(path_id: int, d: float) -> bool:
	var need := float(config["car_length_m"]) + float(config["min_gap_m"])
	for a in agents:
		if a.path_id == path_id and absf(a.distance - d) < need * 2.0:
			return false
	return true


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
