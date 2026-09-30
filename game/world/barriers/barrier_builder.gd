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
	"median": {"thickness": 0.55, "color": Color(0.64, 0.64, 0.62)},
	"guardrail": {"thickness": 0.12, "color": Color(0.55, 0.57, 0.6)},
	"soundwall": {"thickness": 0.3, "color": Color(0.7, 0.64, 0.55)},
}
const DEFAULT_STYLE := {"thickness": 0.3, "color": Color(0.6, 0.6, 0.6)}


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
