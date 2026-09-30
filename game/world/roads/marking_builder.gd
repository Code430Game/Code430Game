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
## polyline in metres. Rules come from marking_rules.json.

const RULES_PATH := "res://world/roads/marking_rules.json"

var rules: Dictionary = {}


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
## for one edge: [{"offset": float, "style": "solid"|"dashed", "color": "yellow"|"white"}].
func lines_for(edge: RoadGraph.RoadEdge) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lanes_total := edge.lanes_forward + edge.lanes_backward
	if lanes_total <= 0:
		return out
	var lane_w := edge.width_m / lanes_total
	var half := edge.width_m * 0.5
	var lw: float = rules["line_width_m"]
	var rule := class_rule(edge.road_class)
	var divider := half - edge.lanes_forward * lane_w  # boundary between directions (or the left edge when one-way)
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
		out.append({"offset": half - lw, "style": "solid", "color": "white"})
		out.append({"offset": -half + lw, "style": "solid", "color": "white"})
	return out


## Builds markings for every edge. Returns chunk -> RoadMeshBuilder.ChunkTriangles.
func build(graph: RoadGraph, junctions: Dictionary) -> Dictionary:
	var buckets := {}
	var lift: float = RoadMeshBuilder.SURFACE_LIFT_M + RoadMeshBuilder.LINK_EXTRA_LIFT_M + float(rules["lift_above_road_m"])
	for eid in graph.sorted_edge_ids():
		var edge: RoadGraph.RoadEdge = graph.edges[eid]
		var trim_start := 0.0
		var trim_end := 0.0
		if junctions.has(edge.from_node):
			trim_start = junctions[edge.from_node].trims.get(eid, 0.0)
		if junctions.has(edge.to_node):
			trim_end = junctions[edge.to_node].trims.get(eid, 0.0)
		var pl := RoadGeometry.trim(edge.polyline, trim_start, trim_end)
		if pl.size() < 2:
			continue
		var normals := RoadGeometry.miter_normals(pl)
		for line in lines_for(edge):
			var offset_pl := PackedVector3Array()
			for i in range(pl.size()):
				var n := normals[i] * float(line["offset"])
				offset_pl.append(pl[i] + Vector3(n.x, lift, n.y))
			var c := color(line["color"])
			if line["style"] == "solid":
				_ribbon(offset_pl, float(rules["line_width_m"]), c, buckets)
			else:
				_dashes(offset_pl, float(rules["line_width_m"]), float(rules["dash_on_m"]), float(rules["dash_off_m"]), c, buckets)
	return buckets


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
static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.8
	m.emission_enabled = true
	m.emission = Color(0.25, 0.25, 0.22)
	m.emission_energy_multiplier = 0.35
	return m
