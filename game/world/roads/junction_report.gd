class_name JunctionReport
extends RefCounted
## Finds junctions that look wrong (update-junction-surfaces), for `--junction-report`, the
## headless `world/build/junction_report.gd` and regression tests.
##
## Approach: for every junction, the outline should stay inside what its arms need: each arm's
## ribbon from its end at the node out to its trim, the region between the arms' end points (a
## clustered junction's core), and between two neighbouring arms either the corner where their
## side lines meet (a rounded corner fills that) or, for arms leaving within a right angle of each
## other, the strip between their ribbons. The bulge is how far the outline reaches beyond that:
## a corner pushed into the grass beside a straight-through road shows as metres of bulge. The
## gap is the other way round: each arm's ribbon is trimmed back to where the outline takes over,
## so any part of the ribbon between the node and its trim that the outline does not cover shows
## grass (a notch, the "C" of a T junction whose corner was pushed back across the road).
## Also listed: hull fallbacks (the outline crossed itself), tiny outlines (point-like junctions),
## nodes of three or more roads with no surface at all that are not forks, and terrain standing
## above the surface. A junction with a tunnel arm is counted apart: terrain over a tunnel mouth
## is the hillside the tunnel goes into, not grass through the road.

## A junction whose outline reaches this far past its arms is listed as bulging.
const BULGE_M := 1.5
## A junction leaving this much of a trimmed arm uncovered is listed as having a gap.
const GAP_M := 0.5
## An outline smaller than this with three or more arms is listed as point-like.
const POINT_AREA_M2 := 4.0
## Terrain this far above the surface shows through it.
const POKE_M := 0.05
## Two neighbouring arms within this angle may legitimately be filled between (ramps, splits).
const FILL_GAP_DEG := 90.0


## One row per junction or junction-like node with any finding, worst first, plus totals in
## the returned "counts". `terrain` (slow: loads terrain chunks) adds the terrain check.
static func analyse(pack: MapPack, terrain: bool = true) -> Dictionary:
	var rows: Array[Dictionary] = []
	var counts := {"junctions": 0, "bulging": 0, "gaps": 0, "hull": 0, "point_like": 0, "no_surface": 0, "terrain": 0, "tunnel": 0}
	var chunks := {}
	if terrain:
		for e in pack.terrain_index.get("chunks", []):
			chunks[Vector2i(int(e["cx"]), int(e["cz"]))] = e
	var loaded := {}
	for nid in pack.graph.sorted_node_ids():
		if pack.graph.degree(nid) < 3:
			continue
		var node: RoadGraph.RoadNode = pack.graph.nodes[nid]
		var row := {"node": nid, "x": node.position.x, "z": node.position.z, "arms": pack.graph.degree(nid), "flags": []}
		var j: JunctionBuilder.Junction = pack.junctions.get(nid)
		if j == null:
			if not pack.graph.is_fork(nid):
				row["flags"].append("no surface")
				counts["no_surface"] += 1
				rows.append(row)
			continue
		counts["junctions"] += 1
		var area := polygon_area(j.polygon_xz)
		var bulge := bulge_m(pack.graph, j)
		row["area_m2"] = area
		row["bulge_m"] = bulge
		if bulge > BULGE_M:
			row["flags"].append("bulge %.1f m" % bulge)
			counts["bulging"] += 1
		var gap := gap_m(pack.graph, j)
		row["gap_m"] = gap
		if gap > GAP_M:
			row["flags"].append("gap %.1f m" % gap)
			counts["gaps"] += 1
		if j.fallback_hull:
			row["flags"].append("hull")
			counts["hull"] += 1
		if area < POINT_AREA_M2:
			row["flags"].append("point-like")
			counts["point_like"] += 1
		var in_tunnel := pack.graph.incident(nid).any(func(eid: String) -> bool: return pack.graph.edges[eid].tunnel)
		if in_tunnel:
			counts["tunnel"] += 1
		if terrain and not in_tunnel:
			var above := terrain_above(pack, j, chunks, loaded)
			row["terrain_m"] = above
			if above > POKE_M:
				row["flags"].append("terrain +%.2f m" % above)
				counts["terrain"] += 1
		if not (row["flags"] as Array).is_empty():
			rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := _score(a)
		var sb := _score(b)
		return sa > sb if sa != sb else str(a["node"]) < str(b["node"]))
	return {"rows": rows, "counts": counts}


## How far the junction's outline reaches beyond what its arms need, in metres (see the top).
static func bulge_m(graph: RoadGraph, j: JunctionBuilder.Junction) -> float:
	var pieces := allowed_pieces(graph, j)
	var worst := 0.0
	for v in j.polygon_xz:
		worst = maxf(worst, _outside(v, pieces))
	return worst


## How far into each arm's trimmed ribbon the outline fails to reach, in metres: points across
## the ribbon between the node and the trim that lie outside the outline, by their distance to it.
static func gap_m(graph: RoadGraph, j: JunctionBuilder.Junction) -> float:
	if j.polygon_xz.size() < 3:
		return 0.0
	# The arms' own ribbons, drawn from their trims outward, are asphalt too: a sample under
	# another arm's ribbon (a narrow Y, overlapping carriageways) is covered.
	var drawn: Array[PackedVector2Array] = []
	for eid in graph.incident(j.node_id):
		var edge: RoadGraph.RoadEdge = graph.edges[eid]
		var d := graph.direction_from(edge, j.node_id)
		var n := Vector2(-d.y, d.x)
		var end := graph.end_point(edge, j.node_id)
		var o := Vector2(end.x, end.z)
		var hw := edge.width_m * 0.5
		var t := float(j.trims.get(eid, 0.0))
		var far := t + JunctionBuilder.MAX_TRIM_M
		drawn.append(PackedVector2Array([o + d * t - n * hw, o + d * far - n * hw, o + d * far + n * hw, o + d * t + n * hw]))
	var worst := 0.0
	for eid in graph.incident(j.node_id):
		var edge: RoadGraph.RoadEdge = graph.edges[eid]
		var d := graph.direction_from(edge, j.node_id)
		var n := Vector2(-d.y, d.x)
		var end := graph.end_point(edge, j.node_id)
		var o := Vector2(end.x, end.z)
		var hw := edge.width_m * 0.5
		var t := float(j.trims.get(eid, 0.0))
		for f: float in [0.3, 0.6, 0.9]:
			for side: float in [-0.8, 0.0, 0.8]:
				var p := o + d * (t * f) + n * (hw * side)
				if Geometry2D.is_point_in_polygon(p, j.polygon_xz):
					continue
				if drawn.any(func(r: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, r)):
					continue
				var near := INF
				for i in range(j.polygon_xz.size()):
					var q := Geometry2D.get_closest_point_to_segment(p, j.polygon_xz[i], j.polygon_xz[(i + 1) % j.polygon_xz.size()])
					near = minf(near, p.distance_to(q))
				worst = maxf(worst, near)
	return worst


## The polygons a junction's outline may cover: arm ribbons out to their trims, the core between
## the arms' end points, and the corner or fill between neighbouring arms.
static func allowed_pieces(graph: RoadGraph, j: JunctionBuilder.Junction) -> Array[PackedVector2Array]:
	var arms: Array[Dictionary] = []
	var centre := Vector2(j.centre.x, j.centre.z)
	for eid in graph.incident(j.node_id):
		var edge: RoadGraph.RoadEdge = graph.edges[eid]
		var dir := graph.direction_from(edge, j.node_id)
		var end := graph.end_point(edge, j.node_id)
		var origin := Vector2(end.x, end.z)
		var probe := origin + dir * JunctionBuilder.SORT_PROBE_M - centre
		arms.append({"dir": dir, "origin": origin, "hw": edge.width_m * 0.5, "trim": float(j.trims.get(eid, JunctionBuilder.TRIM_MARGIN_M)), "bearing": atan2(probe.y, probe.x)})
	arms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["bearing"] < b["bearing"])
	var pieces: Array[PackedVector2Array] = []
	var core := PackedVector2Array()
	for a in arms:
		var d: Vector2 = a["dir"]
		var n := Vector2(-d.y, d.x)
		var o: Vector2 = a["origin"]
		var hw: float = a["hw"]
		var t: float = a["trim"]
		# The ribbon, from a half width behind its end (it meets the core there) out to the trim.
		pieces.append(PackedVector2Array([o - d * hw - n * hw, o + d * t - n * hw, o + d * t + n * hw, o - d * hw + n * hw]))
		core.append(o - n * hw)
		core.append(o + n * hw)
	if core.size() >= 3:
		var hull := Geometry2D.convex_hull(core)
		if hull.size() >= 3:
			pieces.append(hull)
	var count := arms.size()
	for i in range(count):
		var a: Dictionary = arms[i]
		var b: Dictionary = arms[(i + 1) % count]
		var da: Vector2 = a["dir"]
		var db: Vector2 = b["dir"]
		var na := Vector2(-da.y, da.x)
		var nb := Vector2(-db.y, db.x)
		var pa: Vector2 = a["origin"] + na * float(a["hw"])
		var pb: Vector2 = b["origin"] - nb * float(b["hw"])
		var cap_a := pa + da * float(a["trim"])
		var cap_b := pb + db * float(b["trim"])
		var gap := fposmod(atan2(db.y, db.x) - atan2(da.y, da.x), TAU)
		var hit: Variant = Geometry2D.line_intersects_line(pa, da, pb, db)
		if hit != null:
			# Where the two edges cross (a little behind one arm's end counts, as in the builder),
			# the rounded corner lies within the caps and that crossing.
			var x: Vector2 = hit
			var ta := (x - pa).dot(da)
			var tb := (x - pb).dot(db)
			var reach := minf(JunctionBuilder.MAX_CORNER_HALF_WIDTHS * maxf(float(a["hw"]), float(b["hw"])), JunctionBuilder.MAX_TRIM_M)
			if ta >= -reach and tb >= -reach and ta <= float(a["trim"]) + 0.01 and tb <= float(b["trim"]) + 0.01:
				var corner := Geometry2D.convex_hull(PackedVector2Array([pa, cap_a, x, cap_b, pb]))
				if corner.size() >= 3:
					pieces.append(corner)
				continue
		if gap < deg_to_rad(FILL_GAP_DEG):
			pieces.append(PackedVector2Array([pa, cap_a, cap_b, pb]))
	return pieces


## Highest terrain above the junction's surface, sampled 60% and 85% of the way from its centre
## to each outline vertex (the outline itself sits on the 4 m terrain grid's edge). -INF when no
## terrain chunk covers it.
static func terrain_above(pack: MapPack, j: JunctionBuilder.Junction, chunks: Dictionary, loaded: Dictionary) -> float:
	var worst := -INF
	for i in range(j.polygon_xz.size()):
		var v := j.polygon_xz[i]
		for f: float in [0.6, 0.85]:
			var x := lerpf(j.centre.x, v.x, f)
			var z := lerpf(j.centre.z, v.y, f)
			var y := lerpf(j.centre.y, j.heights[i], f)
			var key := RoadGeometry.chunk_of(Vector3(x, 0.0, z))
			if not chunks.has(key):
				continue
			if not loaded.has(key):
				loaded[key] = TerrainBuilder.load_chunk(pack.pack_dir, pack.terrain_index, chunks[key])
			var h: TerrainBuilder.ChunkHeights = loaded[key]
			if h != null:
				worst = maxf(worst, h.sample(x, z) - y)
	return worst


## Area of a simple polygon (shoelace), always positive.
static func polygon_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


## The report as text: totals, then up to `limit` rows with x, z and what was found.
static func format(report: Dictionary, limit: int = 40) -> String:
	var c: Dictionary = report["counts"]
	var lines := PackedStringArray()
	lines.append("junction report: %d junctions; %d bulging > %.1f m, %d with gaps > %.1f m, %d hull fallbacks, %d point-like, %d nodes of 3+ roads with no surface, %d with terrain above (%d at tunnels, not checked)" % [c["junctions"], c["bulging"], BULGE_M, c["gaps"], GAP_M, c["hull"], c["point_like"], c["no_surface"], c["terrain"], c["tunnel"]])
	var rows: Array = report["rows"]
	for r: Dictionary in rows.slice(0, limit):
		lines.append("  %s at x %.0f, z %.0f (%d arms): %s" % [r["node"], r["x"], r["z"], r["arms"], ", ".join(PackedStringArray(r["flags"]))])
	return "\n".join(lines)


static func _score(row: Dictionary) -> float:
	var s := float(row.get("bulge_m", 0.0)) + float(row.get("gap_m", 0.0))
	if "hull" in row["flags"]:
		s += 2.0
	if "no surface" in row["flags"]:
		s += 1.0
	return s + maxf(float(row.get("terrain_m", 0.0)), 0.0)


## Distance from `p` to the nearest piece, 0 inside any.
static func _outside(p: Vector2, pieces: Array[PackedVector2Array]) -> float:
	var best := INF
	for poly in pieces:
		if Geometry2D.is_point_in_polygon(p, poly):
			return 0.0
		for i in range(poly.size()):
			var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
			best = minf(best, p.distance_to(q))
	return best
