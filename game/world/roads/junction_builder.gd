class_name JunctionBuilder
extends RefCounted
## Builds junction polygons and per-edge trim distances.
##
## Approach: at a node with three or more roads, sort the roads by angle. For
## each pair of neighbours, intersect the CCW side line of one with the CW side
## line of the next to get a corner. Each road is trimmed back to the farthest
## corner on its sides (plus a margin) and capped there. The polygon walks
## cap, cap, corner around the node. If the walk is not a simple polygon, the
## convex hull of the same points is used and flagged.
##
## Each arm starts at its edge's actual end point, not at the node. At a merged
## junction the importer leaves each carriageway of a divided road on its own
## straight line beside the node, so side lines, corners and caps are all taken
## from the real ribbons; trims stay distances along the edge from its end.

## Roads stop this far back from the corner intersection so the rounded corner has a curb-like radius.
const TRIM_MARGIN_M := 3.0
const MAX_TRIM_M := 60.0
## Corners are rounded with a quadratic curve from one road's cap to the next, using the
## sharp corner as the control point. More steps = smoother. 0 keeps sharp corners.
const FILLET_STEPS := 4
## A corner may sit at most this many half-widths down the road. Beyond that the
## two roads are nearly parallel (a ramp merge) and their ribbons overlap anyway.
const MAX_CORNER_HALF_WIDTHS := 3.0
## Arms closer than this in angle are merged in the polygon walk (see build_one).
const PARALLEL_ARMS_DEG := 12.0
## Arms are ordered by the bearing of a point this many metres down each arm, seen from the
## node, so two carriageways leaving in the same direction side by side keep their real order.
const SORT_PROBE_M := 20.0


class Junction:
	extends RefCounted
	var node_id: String
	var centre: Vector3
	var polygon_xz: PackedVector2Array
	var heights: PackedFloat32Array  # one per polygon vertex
	var trims: Dictionary  # edge id -> trim metres
	var fallback_hull: bool = false
	var dominant_class: String = "residential"  # class of the widest road meeting here, for colouring


## Computes junctions for every node with degree >= 3, except forks and merges: there the
## importer already peeled the ramp off the through road's edge, so the ribbons cover the node
## and the through road simply tapers across it. Returns node id -> Junction.
static func build_all(graph: RoadGraph) -> Dictionary:
	var out := {}
	for nid in graph.sorted_node_ids():
		if graph.degree(nid) >= 3 and not graph.is_fork(nid):
			out[nid] = build_one(graph, nid)
	return out


## Computes the junction at one node.
static func build_one(graph: RoadGraph, node_id: String) -> Junction:
	var node: RoadGraph.RoadNode = graph.nodes[node_id]
	var centre := Vector2(node.position.x, node.position.z)
	var arms: Array[Dictionary] = []
	for eid in graph.incident(node_id):
		var edge: RoadGraph.RoadEdge = graph.edges[eid]
		var dir := graph.direction_from(edge, node_id)
		var end := graph.end_point(edge, node_id)
		var origin := Vector2(end.x, end.z)
		var probe := origin + dir * SORT_PROBE_M - centre
		arms.append({"edge": eid, "dir": dir, "origin": origin, "angle": atan2(dir.y, dir.x), "bearing": atan2(probe.y, probe.x), "hw": edge.width_m * 0.5})
	arms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["bearing"] < b["bearing"])
	# Two arms leaving at nearly the same angle and overlapping (a road and a ramp sharing a
	# stretch) share one slot in the polygon walk: the corner between them would be a sliver
	# spanning metres. The wider arm stays; the narrower one is trimmed like it. Side-by-side
	# carriageways that do not overlap keep their own slots.
	var merged_into := {}  # dropped edge id -> kept edge id
	var slot := 0
	while arms.size() > 1 and slot < arms.size():
		var a: Dictionary = arms[slot]
		var b: Dictionary = arms[(slot + 1) % arms.size()]
		var gap := fposmod(float(b["angle"]) - float(a["angle"]), TAU)
		if gap < deg_to_rad(PARALLEL_ARMS_DEG) and arms.size() > 2 and _overlap(a, b):
			var keep := a if float(a["hw"]) >= float(b["hw"]) else b
			var drop := b if keep == a else a
			merged_into[drop["edge"]] = keep["edge"]
			arms.erase(drop)
			continue  # re-check the same slot against its new neighbour
		slot += 1
	var count := arms.size()
	var corners: Array[Vector2] = []
	var corner_t: Array[Vector2] = []  # (t along arm i, t along arm i+1)
	var straight: Array[bool] = []  # corner i closes a median between side-by-side carriageways
	for i in range(count):
		var a: Dictionary = arms[i]
		var b: Dictionary = arms[(i + 1) % count]
		var da: Vector2 = a["dir"]
		var db: Vector2 = b["dir"]
		var na := Vector2(-da.y, da.x)  # CCW normal of a
		var nb := Vector2(-db.y, db.x)
		var pa: Vector2 = a["origin"] + na * float(a["hw"])  # a's CCW side line
		var pb: Vector2 = b["origin"] - nb * float(b["hw"])  # b's CW side line
		var hit: Variant = Geometry2D.line_intersects_line(pa, da, pb, db)
		var corner: Vector2
		var ta := 0.0
		var tb := 0.0
		var widest := maxf(float(a["hw"]), float(b["hw"]))
		var cap := minf(MAX_CORNER_HALF_WIDTHS * widest, MAX_TRIM_M)
		if hit != null:
			corner = hit
			ta = (corner - pa).dot(da)
			tb = (corner - pb).dot(db)
		var gap := fposmod(float(b["angle"]) - float(a["angle"]), TAU)
		var side_by_side := gap < deg_to_rad(PARALLEL_ARMS_DEG) or gap > TAU - deg_to_rad(PARALLEL_ARMS_DEG)
		if side_by_side:
			# Carriageways leaving the same way beside each other: the walk closes the median with a
			# straight edge from one cap to the next, and the pair grows neither trim.
			corner = (pa + pb) * 0.5
			ta = 0.0
			tb = 0.0
		elif hit == null or ta < 0.0 or tb < 0.0 or ta > cap or tb > cap:
			# Parallel-ish arms (ramp merges) or a corner behind the node: place the corner a
			# capped distance along the bisector, between the two side offsets.
			var bisector := (da + db)
			bisector = bisector.normalized() if bisector.length_squared() > 1e-9 else da
			corner = (pa + pb) * 0.5 + bisector * minf(cap, widest * 1.5)
			ta = maxf((corner - pa).dot(da), 0.0)
			tb = maxf((corner - pb).dot(db), 0.0)
		corners.append(corner)
		corner_t.append(Vector2(ta, tb))
		straight.append(side_by_side)
	var trims := {}
	for k in range(count):
		var prev := (k - 1 + count) % count
		var t := maxf(corner_t[k].x, corner_t[prev].y) + TRIM_MARGIN_M
		trims[arms[k]["edge"]] = minf(t, MAX_TRIM_M)
	for dropped in merged_into:
		var kept: String = merged_into[dropped]
		while merged_into.has(kept):
			kept = merged_into[kept]  # merged into an arm that was itself merged later
		trims[dropped] = trims[kept]
	var polygon := PackedVector2Array()
	var heights := PackedFloat32Array()
	for i in range(count):
		var a: Dictionary = arms[i]
		var d: Vector2 = a["dir"]
		var n := Vector2(-d.y, d.x)
		var t: float = trims[a["edge"]]
		var edge: RoadGraph.RoadEdge = graph.edges[a["edge"]]
		var h := _height_along(graph, edge, node_id, t)
		var o: Vector2 = a["origin"]
		var cap_minus := o + d * t - n * float(a["hw"])
		var cap_plus := o + d * t + n * float(a["hw"])
		polygon.append(cap_minus)
		heights.append(h)
		polygon.append(cap_plus)
		heights.append(h)
		var b: Dictionary = arms[(i + 1) % count]
		var next_edge: RoadGraph.RoadEdge = graph.edges[b["edge"]]
		var t_next: float = trims[next_edge.id]
		var h_next := _height_along(graph, next_edge, node_id, t_next)
		var db: Vector2 = b["dir"]
		var nb := Vector2(-db.y, db.x)
		var next_cap_minus: Vector2 = b["origin"] + db * t_next - nb * float(b["hw"])
		if straight[i]:
			continue
		# Rounded corner: quadratic curve from this cap to the next road's cap through the sharp corner.
		for k in range(1, FILLET_STEPS + 1):
			var u := float(k) / float(FILLET_STEPS + 1)
			var q := cap_plus.lerp(corners[i], u).lerp(corners[i].lerp(next_cap_minus, u), u)
			polygon.append(q)
			heights.append(lerpf(h, h_next, u))
	var j := Junction.new()
	j.node_id = node_id
	j.centre = node.position
	j.trims = trims
	var widest := -1.0
	for arm in arms:
		if float(arm["hw"]) > widest:
			widest = float(arm["hw"])
			j.dominant_class = graph.edges[arm["edge"]].road_class
	# A walk that crosses itself (big clustered junctions with many arms) still triangulates,
	# but its overlapping triangles carry different arm heights and show as tilted slivers.
	if Geometry2D.triangulate_polygon(polygon).size() == 0 or not _is_simple(polygon):
		var hull := Geometry2D.convex_hull(polygon)
		if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
			hull.remove_at(hull.size() - 1)
		j.polygon_xz = hull
		j.heights = PackedFloat32Array()
		for p in hull:
			j.heights.append(_hull_height(graph, node, arms, p))
		j.fallback_hull = true
	else:
		j.polygon_xz = polygon
		j.heights = heights
	return j


## True when two arms' ribbons overlap side to side, measured across the wider one.
static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	var wide: Dictionary = a if float(a["hw"]) >= float(b["hw"]) else b
	var other: Dictionary = b if wide == a else a
	var d: Vector2 = wide["dir"]
	var lateral := absf((other["origin"] - wide["origin"] as Vector2).dot(Vector2(-d.y, d.x)))
	return lateral < float(a["hw"]) + float(b["hw"])


## True when no two non-adjacent edges of the polygon cross.
static func _is_simple(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue  # adjacent through the wrap
			var c := poly[j]
			var d := poly[(j + 1) % n]
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				return false
	return true


## Height for a hull vertex: the road surface of the arm it lies along, at its distance out,
## so a junction on a slope follows the slope instead of sitting flat at the node's height
## (a flat hull stood a step above the downhill arms).
static func _hull_height(graph: RoadGraph, node: RoadGraph.RoadNode, arms: Array[Dictionary], p: Vector2) -> float:
	var offset := p - Vector2(node.position.x, node.position.z)
	var dist := offset.length()
	if dist < 1e-3 or arms.is_empty():
		return node.position.y
	var dir := offset / dist
	var best: Dictionary = arms[0]
	var best_dot := -INF
	for arm in arms:
		var d: float = (arm["dir"] as Vector2).dot(dir)
		if d > best_dot:
			best_dot = d
			best = arm
	var edge: RoadGraph.RoadEdge = graph.edges[best["edge"]]
	return _height_along(graph, edge, node.id, dist * maxf(best_dot, 0.0))


## Height of the road surface at `distance` metres along the edge from the node.
static func _height_along(graph: RoadGraph, edge: RoadGraph.RoadEdge, node_id: String, distance: float) -> float:
	var pl := edge.polyline
	if edge.from_node != node_id:
		pl = pl.duplicate()
		pl.reverse()
	return RoadGeometry.point_at(pl, distance).y
