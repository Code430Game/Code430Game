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

const TRIM_MARGIN_M := 0.5
const MAX_TRIM_M := 60.0
## A corner may sit at most this many half-widths down the road. Beyond that the
## two roads are nearly parallel (a ramp merge) and their ribbons overlap anyway.
const MAX_CORNER_HALF_WIDTHS := 3.0


class Junction:
	extends RefCounted
	var node_id: String
	var centre: Vector3
	var polygon_xz: PackedVector2Array
	var heights: PackedFloat32Array  # one per polygon vertex
	var trims: Dictionary  # edge id -> trim metres
	var fallback_hull: bool = false


## Computes junctions for every node with degree >= 3. Returns node id -> Junction.
static func build_all(graph: RoadGraph) -> Dictionary:
	var out := {}
	for nid in graph.sorted_node_ids():
		if graph.degree(nid) >= 3:
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
		arms.append({"edge": eid, "dir": dir, "angle": atan2(dir.y, dir.x), "hw": edge.width_m * 0.5})
	arms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["angle"] < b["angle"])
	var count := arms.size()
	var corners: Array[Vector2] = []
	var corner_t: Array[Vector2] = []  # (t along arm i, t along arm i+1)
	for i in range(count):
		var a: Dictionary = arms[i]
		var b: Dictionary = arms[(i + 1) % count]
		var da: Vector2 = a["dir"]
		var db: Vector2 = b["dir"]
		var na := Vector2(-da.y, da.x)  # CCW normal of a
		var nb := Vector2(-db.y, db.x)
		var pa := centre + na * float(a["hw"])  # a's CCW side line
		var pb := centre - nb * float(b["hw"])  # b's CW side line
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
		if hit == null or ta < 0.0 or tb < 0.0 or ta > cap or tb > cap:
			# Parallel-ish arms (ramp merges) or a corner behind the node: place the corner a
			# capped distance along the bisector, between the two side offsets.
			var bisector := (da + db)
			bisector = bisector.normalized() if bisector.length_squared() > 1e-9 else da
			corner = centre + (na * float(a["hw"]) - nb * float(b["hw"])) * 0.5 + bisector * minf(cap, widest * 1.5)
			ta = maxf((corner - pa).dot(da), 0.0)
			tb = maxf((corner - pb).dot(db), 0.0)
		corners.append(corner)
		corner_t.append(Vector2(ta, tb))
	var trims := {}
	for i in range(count):
		var prev := (i - 1 + count) % count
		var t := maxf(corner_t[i].x, corner_t[prev].y) + TRIM_MARGIN_M
		trims[arms[i]["edge"]] = minf(t, MAX_TRIM_M)
	var polygon := PackedVector2Array()
	var heights := PackedFloat32Array()
	for i in range(count):
		var a: Dictionary = arms[i]
		var d: Vector2 = a["dir"]
		var n := Vector2(-d.y, d.x)
		var t: float = trims[a["edge"]]
		var edge: RoadGraph.RoadEdge = graph.edges[a["edge"]]
		var h := _height_along(graph, edge, node_id, t)
		polygon.append(centre + d * t - n * float(a["hw"]))
		heights.append(h)
		polygon.append(centre + d * t + n * float(a["hw"]))
		heights.append(h)
		polygon.append(corners[i])
		var next_edge: RoadGraph.RoadEdge = graph.edges[arms[(i + 1) % count]["edge"]]
		var h_next := _height_along(graph, next_edge, node_id, trims[next_edge.id])
		heights.append((h + h_next) * 0.5)
	var j := Junction.new()
	j.node_id = node_id
	j.centre = node.position
	j.trims = trims
	if Geometry2D.triangulate_polygon(polygon).size() == 0:
		var hull := Geometry2D.convex_hull(polygon)
		if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
			hull.remove_at(hull.size() - 1)
		j.polygon_xz = hull
		j.heights = PackedFloat32Array()
		for p in hull:
			j.heights.append(node.position.y)
		j.fallback_hull = true
	else:
		j.polygon_xz = polygon
		j.heights = heights
	return j


## Height of the road surface at `distance` metres along the edge from the node.
static func _height_along(graph: RoadGraph, edge: RoadGraph.RoadEdge, node_id: String, distance: float) -> float:
	var pl := edge.polyline
	if edge.from_node != node_id:
		pl = pl.duplicate()
		pl.reverse()
	return RoadGeometry.point_at(pl, distance).y
