class_name LaneGraph
extends RefCounted
## Lane-level paths derived from the road graph, for traffic agents.
##
## Each drivable edge yields one path per lane, running in the lane's travel
## direction on the trimmed polyline (so paths end at the junction boundary).
## Forward lanes sit on the right of travel (Canada drives on the right):
## offset from the centreline = divider + (k + 0.5) * lane width, where the
## divider is the boundary between directions. Junctions get connector paths
## (quadratic curves through the junction centre) from every arriving lane to
## every lane of every legal outgoing edge. Dead ends get a U-turn connector.

const CONNECTOR_STEPS := 6
const MIN_PATH_LENGTH_M := 1.0


class LanePath:
	extends RefCounted
	var id: int
	var edge_id: String  # "" for connectors
	var road_class: String
	var lane_index: int = 0
	var is_connector: bool = false
	var straightness: float = 1.0  # connectors: cos of the turn angle, for straight-preferring choice
	var points: PackedVector3Array
	var cumulative: PackedFloat32Array  # distance at each point
	var length: float = 0.0
	var speed_kph: int = 40
	var next: PackedInt32Array = PackedInt32Array()  # ids of paths that may follow this one
	var junction_node: String = ""  # connectors: the node they cross

	func position_at(distance: float) -> Vector3:
		if points.size() < 2:
			return points[0] if points.size() == 1 else Vector3.ZERO
		var d := clampf(distance, 0.0, length)
		var i := 0
		while i < cumulative.size() - 2 and cumulative[i + 1] < d:
			i += 1
		var seg := cumulative[i + 1] - cumulative[i]
		var t := (d - cumulative[i]) / seg if seg > 0.0 else 0.0
		return points[i].lerp(points[i + 1], t)

	func direction_at(distance: float) -> Vector3:
		var a := position_at(maxf(distance - 0.5, 0.0))
		var b := position_at(minf(distance + 0.5, length))
		var d := b - a
		d.y = 0.0
		return d.normalized() if d.length_squared() > 1e-9 else Vector3.FORWARD


var paths: Array[LanePath] = []
var _by_edge_end: Dictionary = {}  # node id -> Array[int] of lane path ids arriving at that node
var _by_edge_start: Dictionary = {}  # node id -> Array[int] of lane path ids leaving that node


## Builds all lane paths and connectors. `junctions` from JunctionBuilder.build_all.
static func build(graph: RoadGraph, junctions: Dictionary) -> LaneGraph:
	var lg := LaneGraph.new()
	for eid in graph.sorted_edge_ids():
		var edge: RoadGraph.RoadEdge = graph.edges[eid]
		var trim_start := 0.0
		var trim_end := 0.0
		if junctions.has(edge.from_node):
			trim_start = junctions[edge.from_node].trims.get(eid, 0.0)
		if junctions.has(edge.to_node):
			trim_end = junctions[edge.to_node].trims.get(eid, 0.0)
		var pl := RoadGeometry.trim(edge.polyline, trim_start, trim_end)
		if pl.size() < 2 or RoadGeometry.length_xz(pl) < MIN_PATH_LENGTH_M:
			continue
		var normals := RoadGeometry.miter_normals(pl)
		var lanes_total := edge.lanes_forward + edge.lanes_backward
		var lane_w := edge.width_m / maxf(lanes_total, 1)
		var divider := edge.width_m * 0.5 - edge.lanes_forward * lane_w
		for k in range(edge.lanes_forward):
			var offset := divider + (k + 0.5) * lane_w
			lg._add_lane(edge, k, _offset_polyline(pl, normals, offset), edge.from_node, edge.to_node)
		for k in range(edge.lanes_backward):
			var offset := divider - (k + 0.5) * lane_w
			var back := _offset_polyline(pl, normals, offset)
			back.reverse()
			lg._add_lane(edge, edge.lanes_forward + k, back, edge.to_node, edge.from_node)
	for nid in graph.sorted_node_ids():
		lg._connect_node(graph, nid)
	return lg


static func _offset_polyline(pl: PackedVector3Array, normals: PackedVector2Array, offset: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(pl.size()):
		var n := normals[i] * offset
		out.append(pl[i] + Vector3(n.x, 0.0, n.y))
	return out


func _add_lane(edge: RoadGraph.RoadEdge, lane_index: int, points: PackedVector3Array, start_node: String, end_node: String) -> LanePath:
	var lp := LanePath.new()
	lp.id = paths.size()
	lp.edge_id = edge.id
	lp.road_class = edge.road_class
	lp.lane_index = lane_index
	lp.speed_kph = edge.speed_kph
	_set_points(lp, points)
	paths.append(lp)
	if not _by_edge_start.has(start_node):
		_by_edge_start[start_node] = []
	_by_edge_start[start_node].append(lp.id)
	if not _by_edge_end.has(end_node):
		_by_edge_end[end_node] = []
	_by_edge_end[end_node].append(lp.id)
	return lp


static func _set_points(lp: LanePath, points: PackedVector3Array) -> void:
	lp.points = points
	lp.cumulative = PackedFloat32Array()
	var d := 0.0
	lp.cumulative.append(0.0)
	for i in range(points.size() - 1):
		d += Vector2(points[i + 1].x - points[i].x, points[i + 1].z - points[i].z).length()
		lp.cumulative.append(d)
	lp.length = d


func _connect_node(graph: RoadGraph, nid: String) -> void:
	var arriving: Array = _by_edge_end.get(nid, [])
	var leaving: Array = _by_edge_start.get(nid, [])
	var centre: Vector3 = graph.nodes[nid].position
	for a_id in arriving:
		var a: LanePath = paths[a_id]
		var made := 0
		for b_id in leaving:
			var b: LanePath = paths[b_id]
			if b.edge_id == a.edge_id:
				continue  # U-turn onto the same road is handled below for dead ends only
			_add_connector(a, b, centre, nid, graph)
			made += 1
		if made == 0:
			# Dead end (or only way out is back the same road): U-turn to a lane leaving along our own edge.
			for b_id in leaving:
				var b: LanePath = paths[b_id]
				if b.edge_id == a.edge_id:
					_add_connector(a, b, centre, nid, graph)


func _add_connector(a: LanePath, b: LanePath, centre: Vector3, nid: String, graph: RoadGraph) -> void:
	var p0 := a.points[a.points.size() - 1]
	var p2 := b.points[0]
	var dir_in := a.direction_at(a.length)
	var dir_out := b.direction_at(0.0)
	# Control point: where the incoming and outgoing lane lines would meet, or the midpoint bent toward the centre.
	var hit: Variant = Geometry2D.line_intersects_line(Vector2(p0.x, p0.z), Vector2(dir_in.x, dir_in.z), Vector2(p2.x, p2.z), Vector2(-dir_out.x, -dir_out.z))
	var ctrl: Vector3
	if hit != null and Vector2(p0.x, p0.z).distance_to(hit) < 60.0:
		ctrl = Vector3(hit.x, (p0.y + p2.y) * 0.5, hit.y)
	else:
		ctrl = (p0 + p2) * 0.5
	var pts := PackedVector3Array()
	for s in range(CONNECTOR_STEPS + 1):
		var t := float(s) / CONNECTOR_STEPS
		pts.append(p0.lerp(ctrl, t).lerp(ctrl.lerp(p2, t), t))
	var c := LanePath.new()
	c.id = paths.size()
	c.edge_id = ""
	c.road_class = a.road_class
	c.is_connector = true
	c.junction_node = nid if graph.degree(nid) >= 3 else ""
	c.straightness = dir_in.dot(dir_out)
	c.speed_kph = mini(a.speed_kph, b.speed_kph)
	_set_points(c, pts)
	c.next.append(b.id)
	paths.append(c)
	a.next.append(c.id)


## Lane paths (not connectors) within `radius` of a position, for spawning.
func lanes_near(position: Vector3, radius: float) -> Array[LanePath]:
	var out: Array[LanePath] = []
	for lp in paths:
		if lp.is_connector or lp.points.is_empty():
			continue
		var mid := lp.position_at(lp.length * 0.5)
		if Vector2(mid.x - position.x, mid.z - position.z).length() <= radius:
			out.append(lp)
	return out


## Picks a following path, preferring straighter turns. Returns -1 at a true dead end.
func choose_next(lp: LanePath, rng: RandomNumberGenerator) -> int:
	if lp.next.is_empty():
		return -1
	var total := 0.0
	var weights := PackedFloat32Array()
	for n in lp.next:
		var w := 0.15 + maxf(paths[n].straightness, 0.0) * 1.0
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in range(lp.next.size()):
		r -= weights[i]
		if r <= 0.0:
			return lp.next[i]
	return lp.next[lp.next.size() - 1]
