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

const THROUGH_COS := 0.85  # within about 32 degrees: carrying straight on, not turning
const CONNECTOR_STEPS := 6
const MIN_PATH_LENGTH_M := 1.0


class LanePath:
	extends RefCounted
	var id: int
	var edge_id: String  # "" for connectors
	var road_class: String
	var lane_index: int = 0
	var is_connector: bool = false
	var bus_only: bool = false  # reserved for buses: cars never enter it
	var parking_only: bool = false  # a parking aisle or driveway: traffic never enters it, players drive it
	var tunnel: bool = false  # underground road: traffic keeps out unless nothing else continues
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

	## Distance along the path of the point nearest `pos` (x, z only) and how far off the path it is.
	func closest(pos: Vector3) -> Vector2:
		var best := Vector2(0.0, INF)
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var l2 := ab.length_squared()
			var t := 0.0
			if l2 > 0.0:
				t = clampf(Vector2(pos.x - a.x, pos.z - a.z).dot(ab) / l2, 0.0, 1.0)
			var q := Vector2(a.x, a.z) + ab * t
			var d := Vector2(pos.x, pos.z).distance_to(q)
			if d < best.y:
				best = Vector2(cumulative[i] + (cumulative[i + 1] - cumulative[i]) * t, d)
		return best

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
		var lane_w := edge.carriageway_m() / maxf(lanes_total, 1)
		var divider := edge.carriageway_offset() + edge.carriageway_m() * 0.5 - edge.lanes_forward * lane_w  # lanes keep off the shoulders
		for k in range(edge.lanes_forward):
			var offset := divider + (k + 0.5) * lane_w
			var lp := lg._add_lane(edge, k, _offset_polyline(pl, normals, offset), edge.from_node, edge.to_node)
			lp.bus_only = edge.bus == "only" or (edge.bus == "lane" and k == edge.bus_lane)
			lp.parking_only = edge.road_class == "parking"
		for k in range(edge.lanes_backward):
			var offset := divider - (k + 0.5) * lane_w
			var back := _offset_polyline(pl, normals, offset)
			back.reverse()
			var lp := lg._add_lane(edge, edge.lanes_forward + k, back, edge.to_node, edge.from_node)
			lp.bus_only = edge.bus == "only"
			lp.parking_only = edge.road_class == "parking"
	for nid in graph.sorted_node_ids():
		lg._connect_node(graph, nid)
	# A connector into a reserved lane is reserved too, so lane choice sees it one step early.
	for lp in lg.paths:
		if lp.is_connector and lp.next.size() == 1:
			lp.bus_only = lg.paths[lp.next[0]].bus_only
			lp.parking_only = lg.paths[lp.next[0]].parking_only
			lp.tunnel = lg.paths[lp.next[0]].tunnel
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
	lp.tunnel = edge.tunnel
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
	# Leaving lanes grouped by their road.
	var by_road := {}
	for b_id in leaving:
		var b: LanePath = paths[b_id]
		if not by_road.has(b.edge_id):
			by_road[b.edge_id] = []
		by_road[b.edge_id].append(b)
	var made := {}  # arriving lane id -> connectors made
	for edge_id: String in by_road:
		var outs: Array = by_road[edge_id]
		var dir_out: Vector3 = (outs[0] as LanePath).direction_at(0.0)
		# Arriving lanes that carry straight on into this road (a road continuing past a node,
		# a fork, a merge, straight across a junction) keep their lane: each joins the lane
		# nearest where it ends, and a lane that only starts here (an added lane) takes the
		# nearest arriving one. All-to-all here let cars hop sideways across lanes over a node a
		# few metres long (#93, #107). Turns still reach every lane of the road they turn into.
		var through: Array = []
		for a_id in arriving:
			var a: LanePath = paths[a_id]
			if a.edge_id == edge_id:
				continue  # U-turns: dead ends only, below
			if a.direction_at(a.length).dot(dir_out) >= THROUGH_COS:
				through.append(a)
			else:
				for b in outs:
					_add_connector(a, b, centre, nid, graph)
				made[a.id] = int(made.get(a.id, 0)) + outs.size()
		var fed := {}
		for a in through:
			var end: Vector3 = (a as LanePath).points[(a as LanePath).points.size() - 1]
			var best: LanePath = _nearest_start(outs, end)
			_add_connector(a, best, centre, nid, graph)
			fed[best.id] = true
			made[a.id] = int(made.get(a.id, 0)) + 1
		if not through.is_empty():
			for b in outs:
				if not fed.has(b.id):
					var nearest: LanePath = _nearest_end(through, (b as LanePath).points[0])
					_add_connector(nearest, b, centre, nid, graph)
	for a_id in arriving:
		var a: LanePath = paths[a_id]
		if int(made.get(a.id, 0)) == 0:
			# Dead end (or only way out is back the same road): U-turn to a lane leaving along our own edge.
			for b_id in leaving:
				var b: LanePath = paths[b_id]
				if b.edge_id == a.edge_id:
					_add_connector(a, b, centre, nid, graph)


## The lane in `lanes` whose first point is nearest `p`.
static func _nearest_start(lanes: Array, p: Vector3) -> LanePath:
	var best: LanePath = lanes[0]
	for l: LanePath in lanes:
		if l.points[0].distance_to(p) < best.points[0].distance_to(p):
			best = l
	return best


## The lane in `lanes` whose last point is nearest `p`.
static func _nearest_end(lanes: Array, p: Vector3) -> LanePath:
	var best: LanePath = lanes[0]
	for l: LanePath in lanes:
		if l.points[l.points.size() - 1].distance_to(p) < best.points[best.points.size() - 1].distance_to(p):
			best = l
	return best


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
	c.junction_node = nid if graph.degree(nid) >= 3 and not graph.is_fork(nid) else ""
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
## Picks a following path, preferring straight ones. `preferred` narrows the candidates
## when any pass it (a bus heads for a bus lane), else `allowed` does (a car keeps out of bus
## lanes); when nothing passes either, any candidate will do.
func choose_next(lp: LanePath, rng: RandomNumberGenerator, allowed: Callable = Callable(), preferred: Callable = Callable()) -> int:
	if lp.next.is_empty():
		return -1
	# Parking aisles and driveways are never traffic's, even when nothing else continues:
	# a street ending in a driveway is a dead end to traffic.
	var options := PackedInt32Array()
	for n in lp.next:
		if not paths[n].parking_only:
			options.append(n)
	if options.is_empty():
		return -1
	var open_options := options
	for test: Callable in [preferred, allowed]:
		if not test.is_valid():
			continue
		var filtered := PackedInt32Array()
		for n in open_options:
			if test.call(paths[n]):
				filtered.append(n)
		if not filtered.is_empty():
			options = filtered
			break
	var total := 0.0
	var weights := PackedFloat32Array()
	for n in options:
		var w := 0.15 + maxf(paths[n].straightness, 0.0) * 1.0
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in range(options.size()):
		r -= weights[i]
		if r <= 0.0:
			return options[i]
	return options[options.size() - 1]
