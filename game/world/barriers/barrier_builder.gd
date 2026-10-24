class_name BarrierBuilder
extends RefCounted
## Extrudes barrier base lines from barriers.v0.json into thin solid walls per
## chunk: two side faces, a top, and end caps. Kinds differ in thickness and
## colour; heights come from the file. Walls are embedded 0.3 m below the base
## line so slopes leave no gaps. Retaining walls (retaining_walls.v0.json,
## add-retaining-walls) are barriers of kind "wall" whose height follows the
## ground behind them: one top per point (`tops_m`), interpolated along the line.

const EMBED_M := 0.3
const WALLS_FILE := "retaining_walls.v0.json"
const STYLE := {
	"curb": {"thickness": 0.25, "color": Color(0.62, 0.62, 0.60)},
	"parapet": {"thickness": 0.35, "color": Color(0.66, 0.66, 0.64)},
	"roadblock": {"thickness": 0.7, "color": Color(0.82, 0.42, 0.12)},  # the district's edge: a road the bbox cut
	"median": {"thickness": 0.55, "color": Color(0.64, 0.64, 0.62)},
	"guardrail": {"thickness": 0.12, "color": Color(0.55, 0.57, 0.6)},
	"soundwall": {"thickness": 0.3, "color": Color(0.7, 0.64, 0.55)},
	"wall": {"thickness": 0.4, "color": Color(0.56, 0.56, 0.54)},  # a retaining wall: concrete, the bridge piers' colour
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
	var border_side: String = ""  # a roadblock where the district border cut the road (add-district-stitching)
	var tops_m: PackedFloat32Array = PackedFloat32Array()  # a retaining wall: its height above each point (empty: height_m throughout)


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
		bar.border_side = str(b.get("border_side", ""))
		for p in b["points"]:
			bar.points.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		out.append(bar)
	return out


## Reads retaining_walls.v0.json as barriers of kind "wall"; empty when the pack has none. A
## wall whose `tops_m` is missing or not as long as its points is skipped with a warning: it
## would be built at the wrong height.
static func load_walls(pack_dir: String) -> Array[Barrier]:
	var out: Array[Barrier] = []
	var path := pack_dir.path_join(WALLS_FILE)
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BarrierBuilder: bad JSON in %s" % path)
		return out
	for w: Dictionary in parsed.get("walls", []):
		var points: Array = w.get("points", [])
		var tops: Variant = w.get("tops_m")
		if not (tops is Array) or (tops as Array).size() != points.size():
			push_warning("BarrierBuilder: wall %s skipped: tops_m missing or not one per point" % str(w.get("id", "?")))
			continue
		var bar := Barrier.new()
		bar.id = str(w["id"])
		bar.kind = "wall"
		bar.height_m = float(w.get("height_m", 0.0))
		bar.edge_id = str(w.get("edge_id", ""))
		for p in points:
			bar.points.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		for t in tops:
			bar.tops_m.append(float(t))
		if bar.height_m <= 0.0:
			bar.height_m = bar.tops_m[bar.tops_m.size() - 1] if bar.tops_m.size() > 0 else 0.0
			for t in bar.tops_m:
				bar.height_m = maxf(bar.height_m, t)
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
		var pl: PackedVector3Array
		var tops: PackedFloat32Array
		if b.tops_m.size() == b.points.size():
			var split := split_with_tops(b.points, b.tops_m)
			pl = split["points"]
			tops = split["tops"]
		else:
			pl = RoadGeometry.split_at_chunk_bounds(b.points)
			tops.resize(pl.size())
			tops.fill(b.height_m)
		var normals := RoadGeometry.miter_normals(pl)
		for i in range(pl.size() - 1):
			var chunk := RoadGeometry.chunk_of_segment(pl[i], pl[i + 1])
			if not buckets.has(chunk):
				buckets[chunk] = RoadMeshBuilder.ChunkTriangles.new()
			_segment(buckets[chunk], pl[i], pl[i + 1], normals[i], normals[i + 1], half, tops[i], tops[i + 1], color, i == 0, i == pl.size() - 2)
	return buckets


## RoadGeometry.split_at_chunk_bounds for a line with a height per point: a point inserted at a
## chunk boundary gets the height interpolated along its segment, so the two halves of a
## retaining wall meet at the boundary. Returns {"points": PackedVector3Array, "tops": PackedFloat32Array}.
static func split_with_tops(points: PackedVector3Array, tops: PackedFloat32Array) -> Dictionary:
	var out_pts := PackedVector3Array()
	var out_tops := PackedFloat32Array()
	if points.size() == 0:
		return {"points": out_pts, "tops": out_tops}
	out_pts.append(points[0])
	out_tops.append(tops[0])
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var ts: Array[float] = []
		for axis in [0, 2]:
			var va := a[axis]
			var vb := b[axis]
			if va == vb:
				continue
			var lo := minf(va, vb)
			var hi := maxf(va, vb)
			var k := int(floor(lo / RoadGeometry.CHUNK_SIZE_M)) + 1
			while k * RoadGeometry.CHUNK_SIZE_M < hi:
				var boundary := k * RoadGeometry.CHUNK_SIZE_M
				if boundary > lo:
					ts.append((boundary - va) / (vb - va))
				k += 1
		ts.sort()
		for t in ts:
			if t > 1e-6 and t < 1.0 - 1e-6:
				var p := a.lerp(b, t)
				if p.distance_squared_to(out_pts[out_pts.size() - 1]) > 1e-8:
					out_pts.append(p)
					out_tops.append(lerpf(tops[i], tops[i + 1], t))
		if b.distance_squared_to(out_pts[out_pts.size() - 1]) > 1e-8:
			out_pts.append(b)
			out_tops.append(tops[i + 1])
	return {"points": out_pts, "tops": out_tops}


static func _segment(out: RoadMeshBuilder.ChunkTriangles, a: Vector3, b: Vector3, na: Vector2, nb: Vector2, half: float, height_a: float, height_b: float, color: Color, cap_start: bool, cap_end: bool) -> void:
	var oa := Vector3(na.x, 0.0, na.y) * half
	var ob := Vector3(nb.x, 0.0, nb.y) * half
	var down := Vector3(0.0, -EMBED_M, 0.0)
	var up_a := Vector3(0.0, height_a, 0.0)
	var up_b := Vector3(0.0, height_b, 0.0)
	# Corners: left/right, bottom/top at a and b.
	var al0 := a + oa + down
	var al1 := a + oa + up_a
	var ar0 := a - oa + down
	var ar1 := a - oa + up_a
	var bl0 := b + ob + down
	var bl1 := b + ob + up_b
	var br0 := b - ob + down
	var br1 := b - ob + up_b
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
