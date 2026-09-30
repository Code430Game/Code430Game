class_name RoadMeshBuilder
extends RefCounted
## Builds road ribbons and junction polygons as triangle lists grouped by chunk.
##
## Approach: each edge is trimmed at its junctions, split at chunk boundaries,
## then extruded to a ribbon using mitered normals. Every quad goes into the
## chunk of its midpoint; shared vertices are bit-identical so chunk seams are
## watertight. Junction polygons are triangulated and go to the node's chunk.

const SURFACE_LIFT_M := 0.02
## When a road changes width at a pass-through node (lane count changes), the wider
## side narrows to the neighbour's width over this distance instead of stepping.
const TAPER_LENGTH_M := 25.0
## Links (ramps) sit slightly higher so their overlap with the road they merge into does not z-fight.
const LINK_EXTRA_LIFT_M := 0.015
const LOD1_TOLERANCE_M := 1.5

const CLASS_COLORS := {
	"motorway": Color(0.22, 0.22, 0.24),
	"motorway_link": Color(0.26, 0.26, 0.28),
	"trunk": Color(0.24, 0.24, 0.26),
	"trunk_link": Color(0.27, 0.27, 0.29),
	"primary": Color(0.30, 0.30, 0.32),
	"primary_link": Color(0.32, 0.32, 0.34),
	"secondary": Color(0.34, 0.34, 0.36),
	"secondary_link": Color(0.35, 0.35, 0.37),
	"tertiary": Color(0.37, 0.37, 0.39),
	"tertiary_link": Color(0.38, 0.38, 0.40),
	"unclassified": Color(0.40, 0.40, 0.42),
	"residential": Color(0.42, 0.42, 0.44),
	"living_street": Color(0.46, 0.44, 0.42),
	"service": Color(0.48, 0.48, 0.48),
}
const JUNCTION_COLOR := Color(0.33, 0.33, 0.35)


## Accumulates triangles for one chunk.
class ChunkTriangles:
	extends RefCounted
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()  # optional, same length as vertices when used
	var uv2s := PackedVector2Array()

	func add_triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
		vertices.append(a)
		vertices.append(b)
		vertices.append(c)
		colors.append(color)
		colors.append(color)
		colors.append(color)
		if uvs.size() > 0:
			_pad_uvs()

	## Triangle with per-vertex UV (metres) and a shared UV2 (treatment, seed).
	func add_triangle_uv(a: Vector3, b: Vector3, c: Vector3, color: Color, ua: Vector2, ub: Vector2, uc: Vector2, uv2: Vector2) -> void:
		_pad_uvs()
		vertices.append(a)
		vertices.append(b)
		vertices.append(c)
		for i in range(3):
			colors.append(color)
			uv2s.append(uv2)
		uvs.append(ua)
		uvs.append(ub)
		uvs.append(uc)

	## Brings the UV arrays up to the vertex count with placeholders (plain triangles added earlier).
	func _pad_uvs() -> void:
		while uvs.size() < vertices.size():
			uvs.append(Vector2.ZERO)
			uv2s.append(Vector2(-1.0, 0.0))

	func add_quad(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, color: Color) -> void:
		add_triangle(a0, b0, a1, color)
		add_triangle(a1, b0, b1, color)

	func is_empty() -> bool:
		return vertices.size() == 0

	## Builds an ArrayMesh with generated normals.
	func to_mesh() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var with_uv := uvs.size() == vertices.size()
		for i in range(vertices.size()):
			st.set_color(colors[i])
			if with_uv:
				st.set_uv(uvs[i])
				st.set_uv2(uv2s[i])
			st.add_vertex(vertices[i])
		st.generate_normals()
		return st.commit()


## Result of a build: chunk -> ChunkTriangles, plus counters.
class Result:
	extends RefCounted
	var roads: Dictionary = {}  # Vector2i -> ChunkTriangles (LOD0)
	var roads_lod1: Dictionary = {}
	var junctions: Dictionary = {}  # Vector2i -> ChunkTriangles
	var edges_built: int = 0
	var edges_skipped_inside_junctions: int = 0
	var junctions_built: int = 0
	var junctions_fallback: int = 0

	func get_bucket(dict: Dictionary, chunk: Vector2i) -> ChunkTriangles:
		if not dict.has(chunk):
			dict[chunk] = ChunkTriangles.new()
		return dict[chunk]


## Builds everything for a graph. `junctions` comes from JunctionBuilder.build_all.
static func build(graph: RoadGraph, junctions: Dictionary) -> Result:
	var result := Result.new()
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
			result.edges_skipped_inside_junctions += 1
			continue
		var dir_start := _continuation_dir(graph, edge, edge.from_node, junctions)
		var dir_end := _continuation_dir(graph, edge, edge.to_node, junctions)
		var color: Color = CLASS_COLORS.get(edge.road_class, Color(0.5, 0.5, 0.5))
		var lift := SURFACE_LIFT_M + (LINK_EXTRA_LIFT_M if edge.road_class.ends_with("_link") else 0.0)
		var taper := taper_for(graph, edge, junctions)
		if float(taper["start"]) >= 0.0 or float(taper["end"]) >= 0.0:
			pl = RoadGeometry.densify_ends(pl, TAPER_LENGTH_M, 5.0)
		_extrude(RoadGeometry.split_at_chunk_bounds(pl), edge.width_m * 0.5, dir_start, dir_end, color, lift, result.roads, result, taper)
		var lod1 := RoadGeometry.simplify(pl, LOD1_TOLERANCE_M)
		_extrude(RoadGeometry.split_at_chunk_bounds(lod1), edge.width_m * 0.5, dir_start, dir_end, color, lift, result.roads_lod1, result, taper)
		result.edges_built += 1
	for nid in junctions.keys():
		var j: JunctionBuilder.Junction = junctions[nid]
		_add_junction(j, result)
	return result


## Half-width targets at each end when the neighbour across a pass-through node is narrower:
## {"start": half width at the start or -1, "end": half width at the end or -1}. Only the wider
## edge tapers, so the seam matches the narrower road exactly.
static func taper_for(graph: RoadGraph, edge: RoadGraph.RoadEdge, junctions: Dictionary) -> Dictionary:
	var out := {"start": -1.0, "end": -1.0}
	for side in ["start", "end"]:
		var node_id := edge.from_node if side == "start" else edge.to_node
		if junctions.has(node_id) or graph.degree(node_id) != 2:
			continue
		for other_id in graph.incident(node_id):
			if other_id == edge.id:
				continue
			var other: RoadGraph.RoadEdge = graph.edges[other_id]
			if other.width_m < edge.width_m - 0.05:
				out[side] = other.width_m * 0.5
	return out


## Half width at `distance` metres from the start of a polyline of `total` length, with tapers.
static func half_width_at(base: float, distance: float, total: float, taper: Dictionary) -> float:
	var hw := base
	var start_hw: float = taper.get("start", -1.0)
	var end_hw: float = taper.get("end", -1.0)
	var taper_len := minf(TAPER_LENGTH_M, total * 0.5)
	if start_hw >= 0.0 and distance < taper_len:
		hw = lerpf(start_hw, base, distance / taper_len)
	if end_hw >= 0.0 and total - distance < taper_len:
		hw = minf(hw, lerpf(end_hw, base, (total - distance) / taper_len))
	return hw


## Direction of the road continuing beyond a pass-through node, pointing into this edge.
static func _continuation_dir(graph: RoadGraph, edge: RoadGraph.RoadEdge, node_id: String, junctions: Dictionary) -> Vector2:
	if junctions.has(node_id) or graph.degree(node_id) != 2:
		return Vector2.ZERO
	for other_id in graph.incident(node_id):
		if other_id == edge.id:
			continue
		var other: RoadGraph.RoadEdge = graph.edges[other_id]
		var away := graph.direction_from(other, node_id)  # points from node into the other edge
		var into_this := -away  # travelling along the other edge toward this node
		if edge.from_node == node_id:
			return into_this
		return -into_this  # at our end, the continuation leaves in the direction we arrive
	return Vector2.ZERO


static func _extrude(pl: PackedVector3Array, half_width: float, dir_start: Vector2, dir_end: Vector2, color: Color, lift: float, buckets: Dictionary, result: Result, taper: Dictionary = {}) -> void:
	if pl.size() < 2:
		return
	var normals := RoadGeometry.miter_normals(pl, dir_start, dir_end)
	var total := RoadGeometry.length_xz(pl)
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var walked := 0.0
	for i in range(pl.size()):
		if i > 0:
			walked += Vector2(pl[i].x - pl[i - 1].x, pl[i].z - pl[i - 1].z).length()
		var hw := half_width_at(half_width, walked, total, taper) if not taper.is_empty() else half_width
		var n := normals[i] * hw
		var p := pl[i] + Vector3(0.0, lift, 0.0)
		left.append(p + Vector3(n.x, 0.0, n.y))
		right.append(p - Vector3(n.x, 0.0, n.y))
	for i in range(pl.size() - 1):
		var chunk := RoadGeometry.chunk_of_segment(pl[i], pl[i + 1])
		var bucket := result.get_bucket(buckets, chunk)
		bucket.add_quad(right[i], left[i], right[i + 1], left[i + 1], color)


static func _add_junction(j: JunctionBuilder.Junction, result: Result) -> void:
	var indices := Geometry2D.triangulate_polygon(j.polygon_xz)
	if indices.size() == 0:
		return
	var chunk := RoadGeometry.chunk_of(j.centre)
	var bucket := result.get_bucket(result.junctions, chunk)
	var color: Color = CLASS_COLORS.get(j.dominant_class, JUNCTION_COLOR)
	for t in range(0, indices.size(), 3):
		var a := _lift(j, indices[t])
		var b := _lift(j, indices[t + 1])
		var c := _lift(j, indices[t + 2])
		# The polygon walks the node clockwise seen from above, and triangulate_polygon keeps
		# that winding, which is Godot's front face.
		bucket.add_triangle(a, b, c, color)
	result.junctions_built += 1
	if j.fallback_hull:
		result.junctions_fallback += 1


static func _lift(j: JunctionBuilder.Junction, i: int) -> Vector3:
	var p := j.polygon_xz[i]
	return Vector3(p.x, j.heights[i] + SURFACE_LIFT_M, p.y)
