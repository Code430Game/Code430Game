class_name BarrierBuilder
extends RefCounted
## Extrudes barrier base lines from barriers.v0.json into thin solid walls per
## chunk: two side faces, a top, and end caps. Kinds differ in thickness and
## colour; heights come from the file. Walls are embedded 0.3 m below the base
## line so slopes leave no gaps.

const EMBED_M := 0.3
const STYLE := {
	"curb": {"thickness": 0.25, "color": Color(0.62, 0.62, 0.60)},
	"parapet": {"thickness": 0.35, "color": Color(0.66, 0.66, 0.64)},
	"roadblock": {"thickness": 0.7, "color": Color(0.82, 0.42, 0.12)},  # the district's edge: a road the bbox cut
	"median": {"thickness": 0.55, "color": Color(0.64, 0.64, 0.62)},
	"guardrail": {"thickness": 0.12, "color": Color(0.55, 0.57, 0.6)},
	"soundwall": {"thickness": 0.3, "color": Color(0.7, 0.64, 0.55)},
}
const DEFAULT_STYLE := {"thickness": 0.3, "color": Color(0.6, 0.6, 0.6)}
## A curb piece left this short after clipping it to the junctions is dropped.
const MIN_CURB_M := 0.5


class Barrier:
	extends RefCounted
	var id: String
	var kind: String
	var height_m: float
	var edge_id: String
	var points: PackedVector3Array


## Reads barriers.v0.json; empty when the pack has none.
static func load_barriers(pack_dir: String) -> Array[Barrier]:
	var out: Array[Barrier] = []
	var path := pack_dir.path_join("barriers.v0.json")
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BarrierBuilder: bad JSON in %s" % path)
		return out
	for b: Dictionary in parsed.get("barriers", []):
		var bar := Barrier.new()
		bar.id = b["id"]
		bar.kind = b["kind"]
		bar.height_m = float(b["height_m"])
		bar.edge_id = b["edge_id"]
		for p in b["points"]:
			bar.points.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		out.append(bar)
	return out


## Curbs cut back to the junction surfaces they cross (update-junction-surfaces): the importer
## keeps a curb wherever a sidewalk runs beside the road and no other road's ribbon covers it,
## which a curved road joining a junction does not, so a curb stood inside the junction. Each
## curb loses the parts inside any junction outline; what is left keeps its heights. Other
## kinds are returned unchanged. `junctions` from JunctionBuilder.build_all.
static func clip_curbs(barriers: Array[Barrier], junctions: Dictionary) -> Array[Barrier]:
	var boxes: Array[Rect2] = []
	var outlines: Array[PackedVector2Array] = []
	for nid in junctions:
		var j: JunctionBuilder.Junction = junctions[nid]
		if j.polygon_xz.size() < 3:
			continue
		var box := Rect2(j.polygon_xz[0], Vector2.ZERO)
		for p in j.polygon_xz:
			box = box.expand(p)
		boxes.append(box.grow(0.5))
		outlines.append(j.polygon_xz)
	var out: Array[Barrier] = []
	for b in barriers:
		if b.kind != "curb" or b.points.size() < 2:
			out.append(b)
			continue
		var flat := PackedVector2Array()
		var box := Rect2(Vector2(b.points[0].x, b.points[0].z), Vector2.ZERO)
		for p in b.points:
			flat.append(Vector2(p.x, p.z))
			box = box.expand(Vector2(p.x, p.z))
		var parts: Array[PackedVector2Array] = [flat]
		for k in range(outlines.size()):
			if not boxes[k].intersects(box.grow(0.5)):
				continue
			var next: Array[PackedVector2Array] = []
			for part in parts:
				for piece in Geometry2D.clip_polyline_with_polygon(part, outlines[k]):
					next.append(piece)
			parts = next
		if parts.size() == 1 and _same_line(parts[0], flat):
			out.append(b)  # nothing cut
			continue
		for i in range(parts.size()):
			var piece := parts[i]
			if piece.size() < 2 or _length_2d(piece) < MIN_CURB_M:
				continue
			var cut := Barrier.new()
			cut.id = "%s:%d" % [b.id, i]
			cut.kind = b.kind
			cut.height_m = b.height_m
			cut.edge_id = b.edge_id
			for p in piece:
				cut.points.append(Vector3(p.x, _height_on(b.points, p), p.y))
			out.append(cut)
	return out


## Height of the 3D line `pl` at its point nearest `p` (x, z).
static func _height_on(pl: PackedVector3Array, p: Vector2) -> float:
	var best := INF
	var y := pl[0].y
	for i in range(pl.size() - 1):
		var a := Vector2(pl[i].x, pl[i].z)
		var c := Vector2(pl[i + 1].x, pl[i + 1].z)
		var q := Geometry2D.get_closest_point_to_segment(p, a, c)
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			var seg := a.distance_to(c)
			var t := a.distance_to(q) / seg if seg > 1e-6 else 0.0
			y = lerpf(pl[i].y, pl[i + 1].y, t)
	return y


## True when two 2D lines have the same points (within a millimetre).
static func _same_line(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i].distance_to(b[i]) > 0.001:
			return false
	return true


static func _length_2d(pl: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(pl.size() - 1):
		s += pl[i].distance_to(pl[i + 1])
	return s


## chunk -> RoadMeshBuilder.ChunkTriangles for all barriers.
static func build(barriers: Array[Barrier]) -> Dictionary:
	var buckets := {}
	for b in barriers:
		if b.points.size() < 2:
			continue
		var style: Dictionary = STYLE.get(b.kind, DEFAULT_STYLE)
		var half := float(style["thickness"]) * 0.5
		var color: Color = style["color"]
		var pl := RoadGeometry.split_at_chunk_bounds(b.points)
		var normals := RoadGeometry.miter_normals(pl)
		for i in range(pl.size() - 1):
			var chunk := RoadGeometry.chunk_of_segment(pl[i], pl[i + 1])
			if not buckets.has(chunk):
				buckets[chunk] = RoadMeshBuilder.ChunkTriangles.new()
			_segment(buckets[chunk], pl[i], pl[i + 1], normals[i], normals[i + 1], half, b.height_m, color, i == 0, i == pl.size() - 2)
	return buckets


static func _segment(out: RoadMeshBuilder.ChunkTriangles, a: Vector3, b: Vector3, na: Vector2, nb: Vector2, half: float, height: float, color: Color, cap_start: bool, cap_end: bool) -> void:
	var oa := Vector3(na.x, 0.0, na.y) * half
	var ob := Vector3(nb.x, 0.0, nb.y) * half
	var down := Vector3(0.0, -EMBED_M, 0.0)
	var up := Vector3(0.0, height, 0.0)
	# Corners: left/right, bottom/top at a and b.
	var al0 := a + oa + down
	var al1 := a + oa + up
	var ar0 := a - oa + down
	var ar1 := a - oa + up
	var bl0 := b + ob + down
	var bl1 := b + ob + up
	var br0 := b - ob + down
	var br1 := b - ob + up
	_quad_facing(out, al0, al1, bl0, bl1, oa.normalized(), color)  # left face, outward = +normal
	_quad_facing(out, ar0, ar1, br0, br1, -oa.normalized(), color)  # right face
	_quad_facing(out, al1, ar1, bl1, br1, Vector3.UP, color)  # top
	if cap_start:
		var back := (a - b)
		back.y = 0.0
		_quad_facing(out, al0, al1, ar0, ar1, back.normalized(), color)
	if cap_end:
		var fwd := (b - a)
		fwd.y = 0.0
		_quad_facing(out, bl0, bl1, br0, br1, fwd.normalized(), color)


## Emits a quad (p0,p1 along one edge; q0,q1 along the other) with the winding whose front normal matches `outward`.
static func _quad_facing(out: RoadMeshBuilder.ChunkTriangles, p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3, outward: Vector3, color: Color) -> void:
	var n := (q1 - p0).cross(q0 - p0)  # Godot front: (c - a) x (b - a) for triangle (a, b, c) = (p0, q0, q1)
	if n.dot(outward) >= 0.0:
		out.add_triangle(p0, q0, q1, color)
		out.add_triangle(p0, q1, p1, color)
	else:
		out.add_triangle(p0, q1, q0, color)
		out.add_triangle(p0, p1, q1, color)


static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.9
	return m
