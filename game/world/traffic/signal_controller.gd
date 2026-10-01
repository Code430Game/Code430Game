class_name SignalController
extends RefCounted
## Two-phase signal cycles for signalised junctions.
##
## Approach: at each junction node with control "signals" and three or more arms, the arms
## are grouped into two phases by axis: the first arm and every arm within 45 degrees of it
## or of its opposite form phase A, the rest phase B. The cycle is A green, amber, all red,
## B green, amber, all red, with per-junction offsets from a hash so the city does not blink
## in step. Agents ask `light(node, edge_id)` for their approach.

enum Light { GREEN, AMBER, RED }

var green_s: float = 14.0
var amber_s: float = 3.0
var all_red_s: float = 1.5
var time: float = 0.0
var _phase_of: Dictionary = {}  # node id -> {edge id -> 0 or 1}
var _offset: Dictionary = {}  # node id -> seconds


func setup(graph: RoadGraph, config: Dictionary) -> void:
	green_s = float(config.get("signal_green_s", green_s))
	amber_s = float(config.get("signal_amber_s", amber_s))
	all_red_s = float(config.get("signal_all_red_s", all_red_s))
	_phase_of.clear()
	_offset.clear()
	for nid in graph.sorted_node_ids():
		var node: RoadGraph.RoadNode = graph.nodes[nid]
		if node.control != "signals" or graph.degree(nid) < 3:
			continue
		var arms: Array = graph.incident(nid)
		var first: Vector2 = graph.direction_from(graph.edges[arms[0]], nid)
		var phases := {}
		for eid in arms:
			var d: Vector2 = graph.direction_from(graph.edges[eid], nid)
			phases[eid] = 0 if absf(d.dot(first)) >= cos(deg_to_rad(45.0)) else 1
		_phase_of[nid] = phases
		_offset[nid] = fmod(float(hash(nid) % 1000) / 1000.0 * cycle_length(), cycle_length())


## Seconds for a full A plus B cycle.
func cycle_length() -> float:
	return 2.0 * (green_s + amber_s + all_red_s)


func is_signalised(node_id: String) -> bool:
	return _phase_of.has(node_id)


func signalised_nodes() -> Array:
	return _phase_of.keys()


## Phase index (0 or 1) of an approach edge at a node; -1 when unknown.
func phase_of(node_id: String, edge_id: String) -> int:
	var phases: Dictionary = _phase_of.get(node_id, {})
	return int(phases.get(edge_id, -1))


func advance(delta: float) -> void:
	time += delta


## Light for the approach `edge_id` into `node_id`; GREEN when the node is not signalised.
func light(node_id: String, edge_id: String) -> int:
	var phase := phase_of(node_id, edge_id)
	if phase < 0:
		return Light.GREEN
	return light_for_phase(node_id, phase)


func light_for_phase(node_id: String, phase: int) -> int:
	var half := green_s + amber_s + all_red_s
	var t := fmod(time + float(_offset.get(node_id, 0.0)), cycle_length())
	var active := 0 if t < half else 1
	if active != phase:
		return Light.RED
	var within := t - half * active
	if within < green_s:
		return Light.GREEN
	if within < green_s + amber_s:
		return Light.AMBER
	return Light.RED
