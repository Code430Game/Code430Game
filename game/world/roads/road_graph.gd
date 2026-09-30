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
	var name: String
	var osm_way_id: int
	var length_m: float


var meta: Dictionary = {}
var nodes: Dictionary = {}  # id -> RoadNode
var edges: Dictionary = {}  # id -> RoadEdge
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
		edge.name = str(e["name"]) if e["name"] != null else ""
		edge.osm_way_id = int(e["osm_way_id"])
		edge.length_m = float(e["length_m"])
		g.edges[edge.id] = edge
		g._incident[edge.from_node].append(edge.id)
		if edge.to_node != edge.from_node:
			g._incident[edge.to_node].append(edge.id)
	return g


static func _vec(p: Array) -> Vector3:
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## Edge ids touching a node.
func incident(node_id: String) -> Array:
	return _incident.get(node_id, [])


## Number of edges touching a node.
func degree(node_id: String) -> int:
	return incident(node_id).size()


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
