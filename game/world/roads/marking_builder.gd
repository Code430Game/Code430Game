class_name MarkingBuilder
extends RefCounted
## Generates lane markings from the road graph as thin quads per chunk.
##
## Approach: each edge is trimmed at its junctions like the road ribbon. Lane
## width is the road width over the lane count. Forward lanes sit on the right
## of the travel direction (Canada drives on the right), so the direction
## divider (yellow centre line) is at half width minus forward lanes times lane
## width. Same-direction dividers are white dashes; edge lines are white solid.
## Lines are built on an offset polyline with mitered normals; dashes walk that
## polyline in metres. Rules come from marking_rules.json. Ramps (links) give way
## where their ribbons overlap a through road: their markings stop there, and the
## through road's edge line breaks into dashes across the ramp's mouth.

const RULES_PATH := "res://world/roads/marking_rules.json"
const BUS_LANE_COLOR := Color(0.46, 0.13, 0.11)

var rules: Dictionary = {}
## Ramps give way to the roads they meet (see `build`); off only to measure what that changes.
var clip_ramps := true


## Loads the rules file. Returns false and logs when it is missing or invalid.
func load_rules(path: String = RULES_PATH) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MarkingBuilder: cannot read %s" % path)
		return false
	rules = parsed
	return true


func color(name: String) -> Color:
	var c: Array = rules["colors"][name]
	return Color(float(c[0]), float(c[1]), float(c[2]))


func class_rule(road_class: String) -> Dictionary:
	return rules["classes"].get(road_class, {"centre_style": "none", "edge_lines": false})


## Signed offsets (metres from the centreline, positive = right of travel) and styles
## for one edge: [{"offset": float, "style": "solid"|"dashed", "color": "yellow"|"white"}];
## edge lines also carry "edge": true.
func lines_for(edge: RoadGraph.RoadEdge) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lanes_total := edge.lanes_forward + edge.lanes_backward
	if lanes_total <= 0:
		return out
	var lane_w := edge.carriageway_m() / lanes_total
	var half := edge.carriageway_m() * 0.5
	var mid := edge.carriageway_offset()  # the lanes' centre; off the centreline when the shoulders differ
	var lw: float = rules["line_width_m"]
	var rule := class_rule(edge.road_class)
	var divider := mid + half - edge.lanes_forward * lane_w  # boundary between directions (or the left edge when one-way)
	if edge.lanes_backward > 0:
		match rule["centre_style"]:
			"single_solid":
				out.append({"offset": divider, "style": "solid", "color": "yellow"})
			"single_dashed":
				out.append({"offset": divider, "style": "dashed", "color": "yellow"})
			"double_solid":
				var gap: float = rules["double_gap_m"]
				out.append({"offset": divider - (gap + lw) * 0.5, "style": "solid", "color": "yellow"})
				out.append({"offset": divider + (gap + lw) * 0.5, "style": "solid", "color": "yellow"})
	for k in range(1, edge.lanes_forward):
		out.append({"offset": divider + k * lane_w, "style": "dashed", "color": "white"})
	for k in range(1, edge.lanes_backward):
		out.append({"offset": divider - k * lane_w, "style": "dashed", "color": "white"})
	if rule["edge_lines"]:
		# At the lanes' edge: just inside the road edge, or just out on a shoulder.
		var right := mid + half + (lw * 0.5 if edge.shoulder_right_m > 0.0 else -lw)
		var left := mid - half - (lw * 0.5 if edge.shoulder_left_m > 0.0 else -lw)
		out.append({"offset": right, "style": "solid", "color": "white", "edge": true})
		out.append({"offset": left, "style": "solid", "color": "white", "edge": true})
	return out


## Builds markings for every edge. Returns chunk -> RoadMeshBuilder.ChunkTriangles.
## Ramps give way to the roads they meet (RoadMeshBuilder.is_link): a ramp's markings stop where
## a through road's ribbon covers them, and a through road's edge line turns to dashes where a
## ramp's ribbon meets it. Both tests sample the line every `cover_sample_m` against a grid of
## the other kind's ribbon segments.
func build(graph: RoadGraph, junctions: Dictionary) -> Dictionary:
	var buckets := {}
	var shapes: Array[Dictionary] = []
	for eid in graph.sorted_edge_ids():
		var shape := _shape(graph, graph.edges[eid], junctions)
		if not shape.is_empty():
			shapes.append(shape)
	var through_cover := {}
	var link_cover := {}
	for shape: Dictionary in shapes:
		_index_ribbon(shape, link_cover if RoadMeshBuilder.is_link(shape["edge"]) else through_cover)
	for shape: Dictionary in shapes:
		_build_edge(shape, through_cover, link_cover, buckets)
	build_crossings(graph, buckets, marking_lift(null), color("white"))
	return buckets


## Height of an edge's markings above its polyline: just above its own ribbon. Through roads
## (and `null`) keep the height they always had, clear of the crossing strips the import lays
## 2 cm above the road; ramps sit lower, under the through road's surface where they overlap it.
func marking_lift(edge: RoadGraph.RoadEdge) -> float:
	var above := float(rules["lift_above_road_m"])
	if edge != null and RoadMeshBuilder.is_link(edge):
		return RoadMeshBuilder.surface_lift(edge) + above
	return RoadMeshBuilder.SURFACE_LIFT_M + RoadMeshBuilder.LINK_UNDER_M + above


## The edge's trimmed, tapered polyline and what the ribbon builder knows about its width:
## {"edge", "pl", "taper", "tapered", "total", "base_hw"}, or {} when nothing is left after trims.
func _shape(graph: RoadGraph, edge: RoadGraph.RoadEdge, junctions: Dictionary) -> Dictionary:
	var trim_start := 0.0
	var trim_end := 0.0
	if junctions.has(edge.from_node):
		trim_start = junctions[edge.from_node].trims.get(edge.id, 0.0)
	if junctions.has(edge.to_node):
		trim_end = junctions[edge.to_node].trims.get(edge.id, 0.0)
	var pl := RoadGeometry.trim(edge.polyline, trim_start, trim_end)
	if pl.size() < 2:
		return {}
	var taper := RoadMeshBuilder.taper_for(graph, edge, junctions)
	var tapered: bool = float(taper["start"]) >= 0.0 or float(taper["end"]) >= 0.0
	if tapered:
		pl = RoadGeometry.densify_ends(pl, RoadMeshBuilder.TAPER_LENGTH_M, 5.0)
	return {"edge": edge, "pl": pl, "taper": taper, "tapered": tapered, "total": RoadGeometry.length_xz(pl), "base_hw": edge.width_m * 0.5}


## Half width of the shape's ribbon `walked` metres along it (tapers included).
static func _half_width(shape: Dictionary, walked: float) -> float:
	var base: float = shape["base_hw"]
	if not shape["tapered"]:
		return base
	return RoadMeshBuilder.half_width_at(base, walked, shape["total"], shape["taper"])


## Adds the shape's ribbon segments to `index` (grid cell -> [[a, b, half width at a, at b]]),
## in every cell the segment's ribbon can reach.
func _index_ribbon(shape: Dictionary, index: Dictionary) -> void:
	var cell := float(rules.get("cover_cell_m", 16.0))
	var pl: PackedVector3Array = shape["pl"]
	var walked := 0.0
	for i in range(pl.size() - 1):
		var a := pl[i]
		var b := pl[i + 1]
		var seg := Vector2(b.x - a.x, b.z - a.z).length()
		var hwa := _half_width(shape, walked)
		var hwb := _half_width(shape, walked + seg)
		walked += seg
		var reach := maxf(hwa, hwb)
		var item := [a, b, hwa, hwb]
		for cx in range(int(floor((minf(a.x, b.x) - reach) / cell)), int(floor((maxf(a.x, b.x) + reach) / cell)) + 1):
			for cz in range(int(floor((minf(a.z, b.z) - reach) / cell)), int(floor((maxf(a.z, b.z) + reach) / cell)) + 1):
				var key := Vector2i(cx, cz)
				if not index.has(key):
					index[key] = []
				index[key].append(item)


## True when `p` (a point on a road, at its polyline height) lies on a ribbon in `index` at the
## same level.
func covered(index: Dictionary, p: Vector3) -> bool:
	var cell := float(rules.get("cover_cell_m", 16.0))
	var max_dy := float(rules.get("cover_max_dy_m", 0.6))
	var q := Vector2(p.x, p.z)
	for item: Array in index.get(Vector2i(int(floor(p.x / cell)), int(floor(p.z / cell))), []):
		var a: Vector3 = item[0]
		var b: Vector3 = item[1]
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var l2 := a2.distance_squared_to(b2)
		var t := 0.0 if l2 < 1e-9 else clampf((q - a2).dot(b2 - a2) / l2, 0.0, 1.0)
		var hw := lerpf(float(item[2]), float(item[3]), t)
		if q.distance_to(a2.lerp(b2, t)) < hw and absf(lerpf(a.y, b.y, t) - p.y) < max_dy:
			return true
	return false


## True when any part of `pl` falls in a cell of `index`, so the per-sample test is worth doing.
func _touches(index: Dictionary, pl: PackedVector3Array) -> bool:
	if index.is_empty():
		return false
	var cell := float(rules.get("cover_cell_m", 16.0))
	for i in range(pl.size() - 1):
		var a := pl[i]
		var b := pl[i + 1]
		var steps := maxi(1, int(ceil(Vector2(b.x - a.x, b.z - a.z).length() / cell)))
		for k in range(steps + 1):
			var p := a.lerp(b, float(k) / steps)
			if index.has(Vector2i(int(floor(p.x / cell)), int(floor(p.z / cell)))):
				return true
	return false


## One edge's lines, clipped and broken where ramps and through roads meet.
func _build_edge(shape: Dictionary, through_cover: Dictionary, link_cover: Dictionary, buckets: Dictionary) -> void:
	var edge: RoadGraph.RoadEdge = shape["edge"]
	var link := RoadMeshBuilder.is_link(edge)
	var other: Dictionary = through_cover if link else link_cover
	var pl: PackedVector3Array = shape["pl"]
	# Ramps are few, so every ramp is tested; a through road only when a ramp's ribbon is near.
	var test := clip_ramps and not other.is_empty() and (link or _touches(other, pl))
	var corner := PackedByteArray()  # 1 for the road's own vertices, 0 for test samples between them
	if test:
		var dense := PackedVector3Array()
		var step := float(rules.get("cover_sample_m", 1.0))
		for i in range(pl.size() - 1):
			dense.append(pl[i])
			corner.append(1)
			var parts := int(ceil(Vector2(pl[i + 1].x - pl[i].x, pl[i + 1].z - pl[i].z).length() / step))
			for k in range(1, parts):
				dense.append(pl[i].lerp(pl[i + 1], float(k) / parts))
				corner.append(0)
		dense.append(pl[pl.size() - 1])
		corner.append(1)
		pl = dense
	var normals := RoadGeometry.miter_normals(pl)
	var base_hw: float = shape["base_hw"]
	var lift := marking_lift(edge)
	var lines := lines_for(edge)
	if edge.bus != "":
		# Bus lanes get a red tint ribbon down the middle of each reserved lane.
		var lanes_total := edge.lanes_forward + edge.lanes_backward
		var lane_w := edge.carriageway_m() / maxf(lanes_total, 1)
		var div := edge.carriageway_offset() + edge.carriageway_m() * 0.5 - edge.lanes_forward * lane_w
		for k in range(edge.lanes_forward):
			if edge.bus == "only" or k == edge.bus_lane:
				lines.append({"offset": div + (k + 0.5) * lane_w, "style": "bus", "color": "white", "width": lane_w - 0.5})
		if edge.bus == "only":
			for k in range(edge.lanes_backward):
				lines.append({"offset": div - (k + 0.5) * lane_w, "style": "bus", "color": "white", "width": lane_w - 0.5})
	var up := Vector3(0.0, lift, 0.0)
	for line in lines:
		var on_road := PackedVector3Array()  # the line's points at road height, for the cover test
		var hit := PackedByteArray()
		var walked := 0.0
		var check := test and (link or bool(line.get("edge", false)))
		for i in range(pl.size()):
			if i > 0:
				walked += Vector2(pl[i].x - pl[i - 1].x, pl[i].z - pl[i - 1].z).length()
			var scale := _half_width(shape, walked) / base_hw if shape["tapered"] else 1.0
			var n := normals[i] * float(line["offset"]) * scale
			on_road.append(pl[i] + Vector3(n.x, 0.0, n.y))
			hit.append(1 if check and covered(other, on_road[i]) else 0)
		if not check:
			var plain := on_road
			if test:  # drop the test samples: the line keeps the road's own corners only
				plain = PackedVector3Array()
				for k in range(on_road.size()):
					if corner[k] == 1:
						plain.append(on_road[k])
			_draw_line(_lifted(plain, up), line, buckets)
			continue
		# Runs of samples in the same state, each ending on the cover's edge (found by bisection)
		# and keeping only the road's own corners in between, so the line has no more quads than
		# before. A ramp's line stops under the through road; a through road's edge line turns to
		# dashes across the ramp's mouth.
		var i := 0
		while i < on_road.size():
			var j := i
			while j + 1 < on_road.size() and hit[j + 1] == hit[i]:
				j += 1
			var run := PackedVector3Array()
			if i > 0:
				run.append(_cover_edge(other, on_road[i - 1], on_road[i]))
			for k in range(i, j + 1):
				if corner[k] == 1 or (k == i and i == 0) or (k == j and j == on_road.size() - 1):
					_append_apart(run, on_road[k])
			if j + 1 < on_road.size():
				_append_apart(run, _cover_edge(other, on_road[j], on_road[j + 1]))
			run = _lifted(run, up)
			if hit[i] == 0:
				_draw_line(run, line, buckets)
			elif not link:
				_draw_line(run, {"style": "dashed", "color": line["color"]}, buckets)
			i = j + 1


## Where the cover test changes between road points `a` and `b` (bisection, to a few centimetres).
func _cover_edge(index: Dictionary, a: Vector3, b: Vector3) -> Vector3:
	var start := covered(index, a)
	var lo := 0.0
	var hi := 1.0
	for _k in range(6):
		var mid := (lo + hi) * 0.5
		if covered(index, a.lerp(b, mid)) == start:
			lo = mid
		else:
			hi = mid
	return a.lerp(b, (lo + hi) * 0.5)


## Appends `p` unless it sits on the run's last point: a near-zero segment would give the line a
## wild mitred corner. A last point that close is replaced, so a boundary still ends the run.
static func _append_apart(run: PackedVector3Array, p: Vector3) -> void:
	if run.size() > 0 and Vector2(p.x - run[run.size() - 1].x, p.z - run[run.size() - 1].z).length() < 0.1:
		run[run.size() - 1] = p
		return
	run.append(p)


static func _lifted(pl: PackedVector3Array, up: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in pl:
		out.append(p + up)
	return out


## Draws one line (solid, dashed or a bus-lane tint) along an offset polyline.
func _draw_line(offset_pl: PackedVector3Array, line: Dictionary, buckets: Dictionary) -> void:
	if offset_pl.size() < 2:
		return
	var c := color(line["color"])
	if line["style"] == "bus":
		_ribbon(offset_pl, float(line["width"]), BUS_LANE_COLOR, buckets)
	elif line["style"] == "solid":
		_ribbon(offset_pl, float(rules["line_width_m"]), c, buckets)
	else:
		_dashes(offset_pl, float(rules["line_width_m"]), float(rules["dash_on_m"]), float(rules["dash_off_m"]), c, buckets)


const ZEBRA_BAR_M := 0.5  # bar thickness across the road; the gap between bars is the same
const ZEBRA_EDGE_M := 0.3  # bars stop this far inside the carriageway's edges
const STOP_LINE_W_M := 0.4
const STOP_LINE_SETBACK_M := 2.0  # from the crossing's near edge
const SIGNAL_REACH_M := 35.0
const CROSSING_REACH_M := 15.0


## Zebra stripes on every crossing (bars across the road, long side along it, like Abbey Road)
## and, where the crossing sits by a signalised junction, a stop line for the traffic heading
## into that junction. Returns how many crossings got stripes.
static func build_crossings(graph: RoadGraph, buckets: Dictionary, lift: float, white: Color) -> int:
	var striped := 0
	for w in graph.pedestrian:
		if w.kind != "crossing" or w.polyline.size() < 2 or w.covered:
			continue
		var a := w.polyline[0]
		var b := w.polyline[w.polyline.size() - 1]
		var mid := (a + b) * 0.5
		var hit := graph.nearest_edge(mid, CROSSING_REACH_M)
		if hit.is_empty():
			continue
		var e: RoadGraph.RoadEdge = hit["edge"]
		if e.road_class == "parking":
			continue
		var at := _closest_on(e.polyline, mid)
		var centre: Vector3 = at[0]
		var t: Vector2 = at[1]  # road direction here (unit, x/z)
		var across := Vector2(-t.y, t.x)
		var hw := e.width_m * 0.5
		var half_len := maxf(w.width_m, 2.0) * 0.5  # bars as long as the crossing is wide
		# On top of the crossing's own strip (the import sets it just above the road).
		var y := maxf(centre.y + lift, maxf(a.y, b.y) + SidewalkBuilder.SURFACE_LIFT_M + 0.008)
		var s := -hw + ZEBRA_EDGE_M + ZEBRA_BAR_M * 0.5
		var bars := 0
		while s <= hw - ZEBRA_EDGE_M - ZEBRA_BAR_M * 0.5 + 0.001:
			var c := Vector2(centre.x, centre.z) + across * s
			var p0 := Vector3(c.x - t.x * half_len, y, c.y - t.y * half_len)
			var p1 := Vector3(c.x + t.x * half_len, y, c.y + t.y * half_len)
			_ribbon(PackedVector3Array([p0, p1]), ZEBRA_BAR_M, white, buckets)
			bars += 1
			s += ZEBRA_BAR_M * 2.0
		if bars > 0:
			striped += 1
		for nid in [e.from_node, e.to_node]:
			if not graph.is_signalised(nid):
				continue
			var j: Vector3 = graph.nodes[nid].position
			if Vector2(j.x - centre.x, j.z - centre.z).length() > SIGNAL_REACH_M:
				continue
			# Traffic heading for the junction meets the crossing first: its stop line sits on the
			# far side of the stripes from the junction, across the lanes to the right of travel.
			var toward := Vector2(j.x - centre.x, j.z - centre.z).normalized()
			var v := t if t.dot(toward) >= 0.0 else -t
			var right := Vector2(-v.y, v.x)
			var base := Vector2(centre.x, centre.z) - v * (half_len + STOP_LINE_SETBACK_M)
			var p0 := Vector3(base.x, y, base.y)
			var p1 := Vector3(base.x + right.x * (hw - ZEBRA_EDGE_M), y, base.y + right.y * (hw - ZEBRA_EDGE_M))
			_ribbon(PackedVector3Array([p0, p1]), STOP_LINE_W_M, white, buckets)
	return striped


## [closest point on the polyline (with its height), unit direction there (x, z)].
static func _closest_on(pl: PackedVector3Array, p: Vector3) -> Array:
	var best := INF
	var out: Array = [pl[0], Vector2(1, 0)]
	for i in range(pl.size() - 1):
		var a := pl[i]
		var b := pl[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var l2 := ab.length_squared()
		if l2 < 1e-6:
			continue
		var f := clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab) / l2, 0.0, 1.0)
		var q := a.lerp(b, f)
		var d := Vector2(p.x - q.x, p.z - q.z).length()
		if d < best:
			best = d
			out = [q, ab.normalized()]
	return out


static func _ribbon(pl: PackedVector3Array, width: float, c: Color, buckets: Dictionary) -> void:
	var split := RoadGeometry.split_at_chunk_bounds(pl)
	var normals := RoadGeometry.miter_normals(split)
	for i in range(split.size() - 1):
		var chunk := RoadGeometry.chunk_of_segment(split[i], split[i + 1])
		if not buckets.has(chunk):
			buckets[chunk] = RoadMeshBuilder.ChunkTriangles.new()
		var n0 := normals[i] * width * 0.5
		var n1 := normals[i + 1] * width * 0.5
		var a0 := split[i] - Vector3(n0.x, 0, n0.y)
		var a1 := split[i] + Vector3(n0.x, 0, n0.y)
		var b0 := split[i + 1] - Vector3(n1.x, 0, n1.y)
		var b1 := split[i + 1] + Vector3(n1.x, 0, n1.y)
		buckets[chunk].add_quad(a0, a1, b0, b1, c)


static func _dashes(pl: PackedVector3Array, width: float, on: float, off: float, c: Color, buckets: Dictionary) -> void:
	var total := RoadGeometry.length_xz(pl)
	var s := 0.0
	while s < total:
		var e := minf(s + on, total)
		if e - s > 0.3:
			var piece := RoadGeometry.trim(pl, s, total - e)
			if piece.size() >= 2:
				_ribbon(piece, width, c, buckets)
		s += on + off


## Material for marking meshes: vertex colours, no shadows, slight emission so they read at dusk.
static func material() -> Material:
	return SurfaceDetail.material("paint", 0.8, Color(0.25, 0.25, 0.22), 0.35)  # worn paint, faint glow
