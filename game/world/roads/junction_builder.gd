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
## Where two neighbouring arms continue each other (a straight-through road at a T, the outside
## of a bend) their side lines are parallel or meet behind the node. The outline then follows
## the road edge, through that meeting point when it is close (the outside of a bend) or straight
## from one cap to the next; pushing a corner off the edge there made a bulge into the grass on
## one side of a T or a notch back across the road on the other (the "ball" and "C" junctions).
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
## Neighbouring arms at least this far apart (counter-clockwise) whose side lines do not meet in
## front of the node continue each other on that side: a road running straight through a T, or
## the outside of a bend. Their outline follows the road edge (update-junction-surfaces, #78/#79).
const STRAIGHT_GAP_DEG := 150.0
## Along a straight-through road, the two roads' edge points at their ends closer than this
## are one point.
const ALONG_MERGE_M := 0.25
## A corner may sit at most this many half-widths down the road. Beyond that the
## two roads are nearly parallel (a ramp merge) and their ribbons overlap anyway.
const MAX_CORNER_HALF_WIDTHS := 3.0
## Arms closer than this in angle are merged in the polygon walk (see build_one).
const PARALLEL_ARMS_DEG := 12.0
## Arms up to this far apart whose ribbons still overlap a little way out (a Y where two roads
## leave the same point at a narrow angle) are joined from one's outer cap corner to the other's:
## their inner cap corners would cross each other.
const SPLIT_ARMS_DEG := 30.0
## Arms are ordered by the bearing of a point this many metres down each arm, seen from the
## node, so two carriageways leaving in the same direction side by side keep their real order.
const SORT_PROBE_M := 20.0


## How the outline gets from one arm's cap to the next one's.
enum Corner {
	FILLET,  ## a rounded corner through the side lines' meeting point
	STRAIGHT,  ## a straight edge from cap to cap, closing the median of side-by-side carriageways
	ALONG,  ## along both roads' edges through their ends: a road running straight on, maybe narrowing
	SHARP,  ## through the side lines' meeting point just behind the node: the outside of a bend
	PAIR,  ## from one arm's outer cap corner to the next's: a Y whose ribbons overlap (SPLIT_ARMS_DEG)
}


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
	# stretch, or a divided road's carriageways whose ribbons touch) share one slot in the polygon
	# walk: the corner between them would be a sliver spanning metres. The slot is the wider arm's
	# direction, widened to cover both ribbons, so neither carriageway's end is left uncovered;
	# the narrower one is trimmed like it. Side-by-side carriageways that do not overlap keep
	# their own slots.
	var merged_into := {}  # dropped edge id -> kept edge id
	var slot := 0
	while arms.size() > 1 and slot < arms.size():
		var a: Dictionary = arms[slot]
		var b: Dictionary = arms[(slot + 1) % arms.size()]
		var gap := fposmod(float(b["angle"]) - float(a["angle"]), TAU)
		if gap < deg_to_rad(PARALLEL_ARMS_DEG) and arms.size() > 2 and _overlap(a, b):
			var keep := a if float(a["hw"]) >= float(b["hw"]) else b
			var drop := b if keep == a else a
			_widen_to_cover(keep, drop)
			merged_into[drop["edge"]] = keep["edge"]
			arms.erase(drop)
			continue  # re-check the same slot against its new neighbour
		slot += 1
	var count := arms.size()
	var corners: Array[Vector2] = []
	var corner_t: Array[Vector2] = []  # (t along arm i, t along arm i+1)
	var kinds: Array[int] = []  # how the outline gets from arm i to arm i+1 (Corner)
	var behind: Array[Vector2i] = []  # 1 where a fillet's crossing lies behind arm i's / arm i+1's end
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
		var kind := Corner.FILLET
		var behind_a := 0
		var behind_b := 0
		if gap < deg_to_rad(SPLIT_ARMS_DEG) and count > 2 and _overlap_out(a, b):
			# A narrow Y: the two ribbons cover the space between them themselves; the outline
			# skips both inner cap corners, which would cross.
			kind = Corner.PAIR
			corner = (pa + pb) * 0.5
			ta = 0.0
			tb = 0.0
		elif gap < deg_to_rad(PARALLEL_ARMS_DEG) or gap > TAU - deg_to_rad(PARALLEL_ARMS_DEG):
			# Carriageways leaving the same way beside each other: the walk closes the median with a
			# straight edge from one cap to the next, and the pair grows neither trim.
			kind = Corner.STRAIGHT
			corner = (pa + pb) * 0.5
			ta = 0.0
			tb = 0.0
		elif gap >= deg_to_rad(STRAIGHT_GAP_DEG) and (hit == null or ta < 0.0 or tb < 0.0 or ta > cap or tb > cap):
			# The two roads continue each other on this side. Their edges meet just behind the node
			# on the outside of a bend: the outline turns there, sharp (a rounded corner would cut
			# into both ribbons). Otherwise (a straight road, the edges parallel) it runs along each
			# edge back to its road's end, stepping across where the road changes width.
			kind = Corner.ALONG
			corner = (pa + pb) * 0.5
			if hit != null and ta <= 0.0 and tb <= 0.0 and -ta < cap and -tb < cap:
				kind = Corner.SHARP
				corner = hit
			ta = 0.0
			tb = 0.0
		elif hit != null and ta >= -cap and tb >= -cap and ta <= cap and tb <= cap:
			# The edges cross; when just behind one arm's end (a narrow road meeting a wide one at an
			# obtuse angle) that is still the corner, and the arm needs no extra trim for it. The
			# walk then runs along that arm's side back to its end before rounding the corner, so
			# the curve does not cut across the arm's own ribbon.
			behind_a = 1 if ta < 0.0 else 0
			behind_b = 1 if tb < 0.0 else 0
			ta = maxf(ta, 0.0)
			tb = maxf(tb, 0.0)
		else:
			# Parallel-ish arms (ramp merges) whose edges meet too far out, or not at all: place the
			# corner a capped distance into the gap between them, between the two side offsets.
			var bisector := da.rotated(gap * 0.5)
			corner = (pa + pb) * 0.5 + bisector * minf(cap, widest * 1.5)
			ta = maxf((corner - pa).dot(da), 0.0)
			tb = maxf((corner - pb).dot(db), 0.0)
		corners.append(corner)
		corner_t.append(Vector2(ta, tb))
		kinds.append(kind)
		behind.append(Vector2i(behind_a, behind_b))
	var trims := {}
	for k in range(count):
		var prev := (k - 1 + count) % count
		var t := maxf(corner_t[k].x, corner_t[prev].y) + TRIM_MARGIN_M
		trims[arms[k]["edge"]] = minf(t, MAX_TRIM_M)
	# The two arms of a narrow Y end level, or the edge from one's outer cap corner to the
	# other's cuts across the longer one.
	for k in range(count):
		if kinds[k] == Corner.PAIR:
			var e1: String = arms[k]["edge"]
			var e2: String = arms[(k + 1) % count]["edge"]
			var level := maxf(trims[e1], trims[e2])
			trims[e1] = level
			trims[e2] = level
	for dropped in merged_into:
		var kept: String = merged_into[dropped]
		while merged_into.has(kept):
			kept = merged_into[kept]  # merged into an arm that was itself merged later
		trims[dropped] = trims[kept]
	var walked := _walk(graph, node_id, arms, trims, corners, kinds, behind)
	var polygon: PackedVector2Array = walked[0]
	var heights: PackedFloat32Array = walked[1]
	if not _usable(polygon) and kinds.has(Corner.ALONG):
		# Stepping back to the roads' ends can cross the outline where a clustered junction's arms
		# start metres from its centre: close those sides straight from cap to cap instead.
		var plain: Array[int] = []
		for k in kinds:
			plain.append(Corner.STRAIGHT if k == Corner.ALONG else k)
		walked = _walk(graph, node_id, arms, trims, corners, plain, behind)
		polygon = walked[0]
		heights = walked[1]
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
	if not _usable(polygon):
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


## The outline from the arms, their trims and how each corner is drawn: [polygon, heights].
static func _walk(graph: RoadGraph, node_id: String, arms: Array[Dictionary], trims: Dictionary, corners: Array[Vector2], kinds: Array[int], behind: Array[Vector2i]) -> Array:
	var count := arms.size()
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
		var prev_arm: Dictionary = arms[(i - 1 + count) % count]
		var next_arm: Dictionary = arms[(i + 1) % count]
		if kinds[(i - 1 + count) % count] == Corner.PAIR:
			# The pair's outer corner on this side is whichever cap reaches further out.
			var other_plus := _cap(prev_arm, trims, 1.0)
			var mean_prev := ((prev_arm["dir"] as Vector2) + d).normalized()
			var across := Vector2(-mean_prev.y, mean_prev.x)
			if other_plus.dot(across) > cap_plus.dot(across):
				cap_plus = other_plus
		else:
			if kinds[i] == Corner.PAIR:
				var other_minus := _cap(next_arm, trims, -1.0)
				var mean_next := (d + (next_arm["dir"] as Vector2)).normalized()
				var across := Vector2(-mean_next.y, mean_next.x)
				if other_minus.dot(across) < cap_minus.dot(across):
					cap_minus = other_minus
			polygon.append(cap_minus)
			heights.append(h)
		if kinds[i] != Corner.PAIR:
			polygon.append(cap_plus)
			heights.append(h)
		var b: Dictionary = arms[(i + 1) % count]
		var next_edge: RoadGraph.RoadEdge = graph.edges[b["edge"]]
		var t_next: float = trims[next_edge.id]
		var h_next := _height_along(graph, next_edge, node_id, t_next)
		var db: Vector2 = b["dir"]
		var nb := Vector2(-db.y, db.x)
		var next_cap_minus: Vector2 = b["origin"] + db * t_next - nb * float(b["hw"])
		if kinds[i] == Corner.STRAIGHT or kinds[i] == Corner.PAIR:
			continue
		if kinds[i] == Corner.ALONG:
			var end_a := o + n * float(a["hw"])
			var end_b: Vector2 = b["origin"] - nb * float(b["hw"])
			var h_end_a := _height_along(graph, edge, node_id, 0.0)
			var h_end_b := _height_along(graph, next_edge, node_id, 0.0)
			if end_a.distance_to(end_b) < ALONG_MERGE_M:
				# The same width on both sides: one point, or the walk zigzags by millimetres.
				polygon.append((end_a + end_b) * 0.5)
				heights.append((h_end_a + h_end_b) * 0.5)
			else:
				polygon.append(end_a)
				heights.append(h_end_a)
				polygon.append(end_b)
				heights.append(h_end_b)
			continue
		if kinds[i] == Corner.SHARP:
			polygon.append(corners[i])
			heights.append(lerpf(h, h_next, 0.5))
			continue
		# Rounded corner: quadratic curve from this cap to the next road's cap through the sharp
		# corner; from or to an arm's end on its side instead when the corner lies behind it.
		var from := cap_plus
		var to := next_cap_minus
		var h_from := h
		var h_to := h_next
		if behind[i].x == 1:
			from = o + n * float(a["hw"])
			h_from = _height_along(graph, edge, node_id, 0.0)
			polygon.append(from)
			heights.append(h_from)
		if behind[i].y == 1:
			to = b["origin"] - nb * float(b["hw"])
			h_to = _height_along(graph, next_edge, node_id, 0.0)
		for k in range(1, FILLET_STEPS + 1):
			var u := float(k) / float(FILLET_STEPS + 1)
			var q := from.lerp(corners[i], u).lerp(corners[i].lerp(to, u), u)
			polygon.append(q)
			heights.append(lerpf(h_from, h_to, u))
		if behind[i].y == 1:
			polygon.append(to)
			heights.append(h_to)
	_dedupe(polygon, heights)
	return [polygon, heights]


## Arm `arm`'s cap corner at its trim: side +1 counter-clockwise, -1 clockwise.
static func _cap(arm: Dictionary, trims: Dictionary, side: float) -> Vector2:
	var d: Vector2 = arm["dir"]
	return (arm["origin"] as Vector2) + d * float(trims[arm["edge"]]) + Vector2(-d.y, d.x) * float(arm["hw"]) * side


## True when the outline triangulates and does not cross itself.
static func _usable(polygon: PackedVector2Array) -> bool:
	return Geometry2D.triangulate_polygon(polygon).size() > 0 and _is_simple(polygon)


## Widens arm `keep` (in place) so its ribbon spans `other`'s too where they start, measured
## across `keep`'s direction: the origin moves sideways to the middle of the combined span.
static func _widen_to_cover(keep: Dictionary, other: Dictionary) -> void:
	var d: Vector2 = keep["dir"]
	var n := Vector2(-d.y, d.x)
	var o: Vector2 = keep["origin"]
	var c := (other["origin"] - o as Vector2).dot(n)
	var lo := minf(-float(keep["hw"]), c - float(other["hw"]))
	var hi := maxf(float(keep["hw"]), c + float(other["hw"]))
	keep["origin"] = o + n * ((lo + hi) * 0.5)
	keep["hw"] = (hi - lo) * 0.5


## Drops vertices within a centimetre of the one before (and the last when it repeats the
## first), or of the straight line between their neighbours in plan and in height, with their
## heights: side-by-side carriageways that touch share a cap corner, and a road running straight
## on puts its end on the line between its caps. A vertex in line in plan but not in height (a
## crest) stays, or the surface would cut through it.
static func _dedupe(poly: PackedVector2Array, heights: PackedFloat32Array) -> void:
	var i := poly.size() - 1
	while i >= 0 and poly.size() > 3:
		var k_prev := (i - 1 + poly.size()) % poly.size()
		var k_next := (i + 1) % poly.size()
		var prev := poly[k_prev]
		var next := poly[k_next]
		var q := Geometry2D.get_closest_point_to_segment(poly[i], prev, next)
		var span := prev.distance_to(next)
		var t := prev.distance_to(q) / span if span > 1e-6 else 0.0
		var level := absf(heights[i] - lerpf(heights[k_prev], heights[k_next], t)) < 0.01
		var on_line := poly[i].distance_to(q) < 0.01 and level
		if poly[i].distance_to(prev) < 0.01 or on_line:
			poly.remove_at(i)
			heights.remove_at(i)
		i = mini(i - 1, poly.size() - 1)


## True when two arms' ribbons still overlap side to side a little way out from their ends
## (twice the wider half width plus the trim margin, about where they would be trimmed),
## measured across the wider one.
static func _overlap_out(a: Dictionary, b: Dictionary) -> bool:
	var wide: Dictionary = a if float(a["hw"]) >= float(b["hw"]) else b
	var other: Dictionary = b if wide == a else a
	var d: Vector2 = wide["dir"]
	var out := 2.0 * float(wide["hw"]) + TRIM_MARGIN_M
	var p_wide: Vector2 = wide["origin"] + d * out
	var p_other: Vector2 = other["origin"] + (other["dir"] as Vector2) * out
	var lateral := absf((p_other - p_wide).dot(Vector2(-d.y, d.x)))
	return lateral < float(a["hw"]) + float(b["hw"])


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
