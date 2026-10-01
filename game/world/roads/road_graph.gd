class_name RoadGraph
extends RefCounted
## In-memory road graph loaded from road_graph.v0.json (see docs/pack-format).
## Positions are local metres: x east, y up, z south.


class RoadNode:
	extends RefCounted
	var id: String
	var position: Vector3
	var ground_y: float
	var junction_type: String
	var control: String = "none"  # signals | stop | give_way | none


class RoadEdge:
	extends RefCounted
	var id: String
	var from_node: String
	var to_node: String
	var polyline: PackedVector3Array
	var road_class: String
	var lanes_forward: int
	var lanes_backward: int
	var oneway: bool
	var speed_kph: int
	var width_m: float
	var layer: int
	var bridge: bool
	var tunnel: bool
	var control_to: String = "none"  # stop | signals | none for traffic arriving at to_node
	var control_from: String = "none"
	var name: String
	var osm_way_id: int
	var length_m: float


class PedestrianWay:
	extends RefCounted
	var id: String
	var polyline: PackedVector3Array
	var road_class: String
	var kind: String  # sidewalk | crossing | footway | path | steps | cycleway | pedestrian | track
	var covered: bool = false  # passes under a road or building: not drawn as a ribbon
	var profile: String = ""  # "tunnel": a dug passage (UnderpassBuilder); "trench": ramps down to one
	var top: PackedFloat32Array = PackedFloat32Array()  # tunnel ceiling height per point
	var width_m: float
	var name: String


var meta: Dictionary = {}
var nodes: Dictionary = {}  # id -> RoadNode
var edges: Dictionary = {}  # id -> RoadEdge
var pedestrian: Array[PedestrianWay] = []
var _incident: Dictionary = {}  # node id -> Array[String] of edge ids


## Loads a graph from an absolute or res:// path. Returns null and logs on failure.
static func load_from_file(path: String) -> RoadGraph:
	if not FileAccess.file_exists(path):
		push_error("RoadGraph: file not found: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("RoadGraph: not a JSON object: %s" % path)
		return null
	return from_dict(parsed)


## Builds a graph from the parsed JSON dictionary.
static func from_dict(data: Dictionary) -> RoadGraph:
	var g := RoadGraph.new()
	g.meta = data.get("meta", {})
	for n: Dictionary in data.get("nodes", []):
		var node := RoadNode.new()
		node.id = n["id"]
		node.position = _vec(n["position"])
		node.ground_y = float(n.get("ground_y", 0.0))
		node.junction_type = n.get("junction_type", "junction")
		node.control = str(n.get("control", "none"))
		g.nodes[node.id] = node
		g._incident[node.id] = []
	for e: Dictionary in data.get("edges", []):
		var edge := RoadEdge.new()
		edge.id = e["id"]
		edge.from_node = e["from"]
		edge.to_node = e["to"]
		var pl := PackedVector3Array()
		for p in e["polyline"]:
			pl.append(_vec(p))
		edge.polyline = pl
		edge.road_class = e["class"]
		edge.lanes_forward = int(e["lanes_forward"])
		edge.lanes_backward = int(e["lanes_backward"])
		edge.oneway = bool(e["oneway"])
		edge.speed_kph = int(e["speed_kph"])
		edge.width_m = float(e["width_m"])
		edge.layer = int(e["layer"])
		edge.bridge = bool(e["bridge"])
		edge.tunnel = bool(e["tunnel"])
		edge.control_to = str(e.get("control_to", "none"))
		edge.control_from = str(e.get("control_from", "none"))
		edge.name = str(e["name"]) if e["name"] != null else ""
		edge.osm_way_id = int(e["osm_way_id"])
		edge.length_m = float(e["length_m"])
		g.edges[edge.id] = edge
		g._incident[edge.from_node].append(edge.id)
		if edge.to_node != edge.from_node:
			g._incident[edge.to_node].append(edge.id)
	for w: Dictionary in data.get("pedestrian_ways", []):
		var pw := PedestrianWay.new()
		pw.id = w["id"]
		var pl := PackedVector3Array()
		for pt in w["polyline"]:
			pl.append(_vec(pt))
		pw.polyline = pl
		pw.road_class = w["class"]
		pw.kind = w.get("kind", "footway")
		pw.width_m = float(w.get("width_m", 1.5))
		pw.covered = bool(w.get("covered", false))
		pw.profile = str(w.get("profile", ""))
		for t in w.get("top", []):
			pw.top.append(float(t))
		pw.name = str(w["name"]) if w.get("name") != null else ""
		g.pedestrian.append(pw)
	return g


static func _vec(p: Array) -> Vector3:
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## Edge ids touching a node.
func incident(node_id: String) -> Array:
	return _incident.get(node_id, [])


## Number of edges touching a node.
func degree(node_id: String) -> int:
	return incident(node_id).size()


## Control a car meets when it reaches `node_id` along `edge`: signals if the junction has
## signals on the node or any approach, else the approach's own stop (or an all-way stop on
## the node), else none.
func approach_control(edge: RoadEdge, node_id: String) -> String:
	if is_signalised(node_id):
		return "signals"
	var own := edge.control_to if edge.to_node == node_id else edge.control_from
	if own == "stop" or nodes[node_id].control == "stop":
		return "stop"
	return "none"


## True when the node or any approach into it carries traffic signals.
func is_signalised(node_id: String) -> bool:
	if nodes[node_id].control == "signals":
		return true
	for eid in incident(node_id):
		var e: RoadEdge = edges[eid]
		if (e.to_node == node_id and e.control_to == "signals") or (e.from_node == node_id and e.control_from == "signals"):
			return true
	return false


## True at a node the importer tagged as a fork (ramp leaving) or merge (ramp arriving).
func is_fork(node_id: String) -> bool:
	var t: String = nodes[node_id].junction_type
	return t == "fork" or t == "merge"


## At a fork or merge, the edge that continues straight through from `edge`: the incident
## edge whose direction is most opposite. Returns "" when `edge` is the ramp (its partner
## would be a through edge, not a continuation) or the node is not a fork.
func through_partner(edge: RoadEdge, node_id: String) -> String:
	if not is_fork(node_id):
		return ""
	var mine := direction_from(edge, node_id)
	var best := ""
	var best_dot := 1.0
	var ramp := ""
	var narrowest := INF
	for other_id in incident(node_id):
		var other: RoadEdge = edges[other_id]
		if other.width_m < narrowest:
			narrowest = other.width_m
			ramp = other_id
		if other_id == edge.id:
			continue
		var d := mine.dot(direction_from(other, node_id))
		if d < best_dot:
			best_dot = d
			best = other_id
	if edge.id == ramp:
		return ""
	return best


## Unit direction (xz plane) of an edge leaving the given node, and the edge's
## first point away from the node. Returns {"dir": Vector2, "next": Vector3}.
func direction_from(edge: RoadEdge, node_id: String) -> Vector2:
	var pl := edge.polyline
	var a: Vector3
	var b: Vector3
	if edge.from_node == node_id:
		a = pl[0]
		b = pl[1]
	else:
		a = pl[pl.size() - 1]
		b = pl[pl.size() - 2]
	var d := Vector2(b.x - a.x, b.z - a.z)
	return d.normalized() if d.length_squared() > 0.0 else Vector2.RIGHT


const INDEX_CELL_M := 64.0
var _segment_index: Dictionary = {}  # Vector2i cell -> Array of [edge id, segment index]


## Nearest edge to a position in the xz plane. Returns {"edge": RoadEdge, "distance": float,
## "point": Vector3, "t": float along the polyline in metres}, or {} when nothing is within `radius`.
func nearest_edge(position: Vector3, radius: float = 60.0) -> Dictionary:
	if _segment_index.is_empty():
		_build_segment_index()
	var p := Vector2(position.x, position.z)
	var best := {}
	var best_d := radius
	var cells := int(ceil(radius / INDEX_CELL_M))
	var centre := Vector2i(int(floor(p.x / INDEX_CELL_M)), int(floor(p.y / INDEX_CELL_M)))
	for dx in range(-cells, cells + 1):
		for dz in range(-cells, cells + 1):
			for item in _segment_index.get(Vector2i(centre.x + dx, centre.y + dz), []):
				var e: RoadEdge = edges[item[0]]
				var i: int = item[1]
				var a := Vector2(e.polyline[i].x, e.polyline[i].z)
				var b := Vector2(e.polyline[i + 1].x, e.polyline[i + 1].z)
				var q := Geometry2D.get_closest_point_to_segment(p, a, b)
				var d := q.distance_to(p)
				if d < best_d:
					best_d = d
					var t := a.distance_to(q)
					var y := lerpf(e.polyline[i].y, e.polyline[i + 1].y, t / maxf(a.distance_to(b), 0.001))
					best = {"edge": e, "distance": d, "point": Vector3(q.x, y, q.y), "segment": i, "t": t}
	return best


func _build_segment_index() -> void:
	for eid in edges:
		var e: RoadEdge = edges[eid]
		for i in range(e.polyline.size() - 1):
			var a := e.polyline[i]
			var b := e.polyline[i + 1]
			for cx in range(int(floor(minf(a.x, b.x) / INDEX_CELL_M)), int(floor(maxf(a.x, b.x) / INDEX_CELL_M)) + 1):
				for cz in range(int(floor(minf(a.z, b.z) / INDEX_CELL_M)), int(floor(maxf(a.z, b.z) / INDEX_CELL_M)) + 1):
					var key := Vector2i(cx, cz)
					if not _segment_index.has(key):
						_segment_index[key] = []
					_segment_index[key].append([eid, i])


## Sorted edge ids for deterministic iteration.
func sorted_edge_ids() -> Array:
	var ids := edges.keys()
	ids.sort()
	return ids


## Sorted node ids for deterministic iteration.
func sorted_node_ids() -> Array:
	var ids := nodes.keys()
	ids.sort()
	return ids
