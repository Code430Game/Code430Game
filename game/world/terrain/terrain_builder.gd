class_name TerrainBuilder
extends RefCounted
## Decodes per-chunk heightmap PNGs (see terrain.json in a map pack) and builds
## grid meshes at three LODs. Row 0 of the image is the north edge (min z).

const LOD_STEPS := [1, 2, 4]  # sample stride per LOD
const TERRAIN_COLOR := Color(0.30, 0.36, 0.26)


## One chunk's decoded heights.
class ChunkHeights:
	extends RefCounted
	var cx: int
	var cz: int
	var samples: int
	var resolution_m: float
	var heights := PackedFloat32Array()  # row-major, samples x samples

	func height_at(row: int, col: int) -> float:
		return heights[row * samples + col]

	## Bilinear height at a local position; clamps to the chunk.
	func sample(x: float, z: float) -> float:
		var fx := clampf((x - cx * (samples - 1) * resolution_m) / resolution_m, 0.0, samples - 1.001)
		var fz := clampf((z - cz * (samples - 1) * resolution_m) / resolution_m, 0.0, samples - 1.001)
		var c0 := int(fx)
		var r0 := int(fz)
		var tx := fx - c0
		var tz := fz - r0
		var top := lerpf(height_at(r0, c0), height_at(r0, c0 + 1), tx)
		var bottom := lerpf(height_at(r0 + 1, c0), height_at(r0 + 1, c0 + 1), tx)
		return lerpf(top, bottom, tz)


## Reads terrain.json from a pack folder. Returns {} on failure.
static func load_index(pack_dir: String) -> Dictionary:
	var path := pack_dir.path_join("terrain.json")
	if not FileAccess.file_exists(path):
		push_error("TerrainBuilder: missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Decodes one chunk entry from the index.
static func load_chunk(pack_dir: String, index: Dictionary, entry: Dictionary) -> ChunkHeights:
	var img := Image.new()
	var bytes := FileAccess.get_file_as_bytes(pack_dir.path_join(entry["file"]))
	if img.load_png_from_buffer(bytes) != OK:
		push_error("TerrainBuilder: bad PNG %s" % entry["file"])
		return null
	var ch := ChunkHeights.new()
	ch.cx = int(entry["cx"])
	ch.cz = int(entry["cz"])
	ch.samples = int(index["samples_per_chunk"])
	ch.resolution_m = float(index["resolution_m"])
	var min_y := float(entry["min_y"])
	var max_y := float(entry["max_y"])
	ch.heights.resize(ch.samples * ch.samples)
	for r in range(ch.samples):
		for c in range(ch.samples):
			var px := img.get_pixel(c, r)
			var q := float(px.r8 * 256 + px.g8)
			ch.heights[r * ch.samples + c] = q / 65535.0 * (max_y - min_y) + min_y
	return ch


## Builds the grid mesh for a chunk at the given LOD (0, 1, 2). `holes` are strips to leave
## out (tunnel passages): [{"a": Vector2, "b": Vector2, "half": float}] in xz; a quad is
## skipped when its centre lies in the rectangle `half` either side of the segment a-b
## (not beyond its ends: the approach cuttings keep their ground). A hole with `"clip": true`
## (garage ramps) is cut exactly instead: a quad it touches keeps the part outside the strip,
## so the cut stops at the strip's edge, under the ramp's coping, at every LOD.
static func build_mesh(ch: ChunkHeights, lod: int, holes: Array = []) -> ArrayMesh:
	var step: int = LOD_STEPS[lod]
	var n := (ch.samples - 1) / step + 1
	var x0 := ch.cx * (ch.samples - 1) * ch.resolution_m
	var z0 := ch.cz * (ch.samples - 1) * ch.resolution_m
	var cell_m := step * ch.resolution_m
	var chunk_m := (ch.samples - 1) * ch.resolution_m
	var plain: Array = []
	var clips: Array = []  # [{"rect": PackedVector2Array, "box": Rect2}]
	for h: Dictionary in holes:
		if h.get("clip", false):
			var rect := strip_rect(h)
			if rect.size() == 4:
				clips.append({"rect": rect, "box": _bounds(rect)})
		else:
			plain.append(h)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	uvs.resize(n * n)
	for r in range(n):
		for c in range(n):
			var row := r * step
			var col := c * step
			verts[r * n + c] = Vector3(x0 + col * ch.resolution_m, ch.height_at(row, col), z0 + row * ch.resolution_m)
			uvs[r * n + c] = Vector2(float(c) / (n - 1), float(r) / (n - 1))
	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var k := 0
	var extra: Array = []
	for r in range(n - 1):
		for c in range(n - 1):
			var i0 := r * n + c
			var i1 := i0 + 1
			var i2 := i0 + n
			var i3 := i2 + 1
			if not plain.is_empty() and _in_hole(plain, (verts[i0] + verts[i3]) * 0.5):
				continue
			if not clips.is_empty():
				var cell := Rect2(verts[i0].x, verts[i0].z, cell_m, cell_m)
				var cutters: Array = []
				for clip: Dictionary in clips:
					if (clip["box"] as Rect2).intersects(cell):
						cutters.append(clip["rect"])
				if not cutters.is_empty():
					var cut := _cut_cell(cell, cutters, [verts[i0], verts[i1], verts[i2], verts[i3]], [i0, i1, i2, i3], extra, n * n)
					indices.resize(indices.size() + cut.size())
					for idx in cut:
						indices[k] = idx
						k += 1
					continue
			# Godot front faces are clockwise seen from outside (here: from above, +y).
			indices[k] = i0
			indices[k + 1] = i1
			indices[k + 2] = i2
			indices[k + 3] = i1
			indices[k + 4] = i3
			indices[k + 5] = i2
			k += 6
	indices.resize(k)
	for p: Vector3 in extra:  # vertices on the cut edges
		verts.append(p)
		uvs.append(Vector2(p.x - x0, p.z - z0) / chunk_m)
	var normals := _normals(verts, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The rectangle a hole strip covers in xz: `half` either side of a-b, from a to b.
static func strip_rect(h: Dictionary) -> PackedVector2Array:
	var a: Vector2 = h["a"]
	var b: Vector2 = h["b"]
	if a.distance_squared_to(b) == 0.0:
		return PackedVector2Array()
	var d := (b - a).normalized()
	var side := Vector2(-d.y, d.x) * float(h["half"])
	return PackedVector2Array([a - side, b - side, b + side, a + side])


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## Triangles (as indices, appending new vertices) for one grid quad less the cutting strips.
## The quad is split on its i1-i2 diagonal like an uncut one, each half is planar, and the
## pieces left over are convex, so each becomes a fan; corners reuse the grid's vertices.
static func _cut_cell(cell: Rect2, cutters: Array, corners: Array, corner_idx: Array, extra: Array, base: int) -> PackedInt32Array:
	var c0: Vector3 = corners[0]
	var c1: Vector3 = corners[1]
	var c2: Vector3 = corners[2]
	var c3: Vector3 = corners[3]
	var p0 := cell.position
	var p1 := p0 + Vector2(cell.size.x, 0.0)
	var p2 := p0 + Vector2(0.0, cell.size.y)
	var p3 := p0 + cell.size
	var out := PackedInt32Array()
	# Two halves: (i0, i1, i2) and (i1, i3, i2).
	var halves := [PackedVector2Array([p0, p1, p2]), PackedVector2Array([p1, p3, p2])]
	for hi in range(2):
		var pieces: Array[PackedVector2Array] = [halves[hi]]
		for rect: PackedVector2Array in cutters:
			var next: Array[PackedVector2Array] = []
			for piece in pieces:
				next.append_array(subtract_convex(piece, rect))
			pieces = next
		for piece in pieces:
			var ids := PackedInt32Array()
			for q in piece:
				ids.append(_vertex_for(q, cell, c0, c1, c2, c3, corner_idx, extra, base))
			for t in range(1, piece.size() - 1):
				var a := piece[0]
				var b := piece[t]
				var c := piece[t + 1]
				var cross := (b - a).cross(c - a)
				if absf(cross) < 1e-6:
					continue
				# Same winding as the grid's quads: (b - a) x (c - a) > 0 in (x, z).
				out.append(ids[0])
				if cross > 0.0:
					out.append(ids[t])
					out.append(ids[t + 1])
				else:
					out.append(ids[t + 1])
					out.append(ids[t])
	return out


static func _vertex_for(q: Vector2, cell: Rect2, c0: Vector3, c1: Vector3, c2: Vector3, c3: Vector3, corner_idx: Array, extra: Array, base: int) -> int:
	var u := (q.x - cell.position.x) / cell.size.x
	var v := (q.y - cell.position.y) / cell.size.y
	const EPS := 1e-4
	if absf(u) < EPS and absf(v) < EPS:
		return corner_idx[0]
	if absf(u - 1.0) < EPS and absf(v) < EPS:
		return corner_idx[1]
	if absf(u) < EPS and absf(v - 1.0) < EPS:
		return corner_idx[2]
	if absf(u - 1.0) < EPS and absf(v - 1.0) < EPS:
		return corner_idx[3]
	# Height on the plane of the half the point is in (the quad's i1-i2 diagonal is u + v = 1).
	var y: float
	if u + v <= 1.0:
		y = c0.y + (c1.y - c0.y) * u + (c2.y - c0.y) * v
	else:
		y = c3.y + (c2.y - c3.y) * (1.0 - u) + (c1.y - c3.y) * (1.0 - v)
	extra.append(Vector3(q.x, y, q.y))
	return base + extra.size() - 1


## Convex `poly` less the convex quad `rect`: up to four convex pieces, one past each of the
## rect's edges (each also inside the edges before it, so the pieces do not overlap).
static func subtract_convex(poly: PackedVector2Array, rect: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var centre := (rect[0] + rect[1] + rect[2] + rect[3]) * 0.25
	var rest := poly
	for i in range(rect.size()):
		var a := rect[i]
		var e := rect[(i + 1) % rect.size()] - a
		var nrm := Vector2(-e.y, e.x)
		if nrm.dot(centre - a) > 0.0:
			nrm = -nrm  # outward
		var piece := _clip_half(rest, a, nrm)
		if piece.size() >= 3 and absf(_area(piece)) > 1e-4:
			out.append(piece)
		rest = _clip_half(rest, a, -nrm)
		if rest.size() < 3:
			break
	return out


## The part of convex `poly` where (p - a) . nrm >= 0 (Sutherland-Hodgman, one edge).
static func _clip_half(poly: PackedVector2Array, a: Vector2, nrm: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in range(n):
		var p := poly[i]
		var q := poly[(i + 1) % n]
		var dp := (p - a).dot(nrm)
		var dq := (q - a).dot(nrm)
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			out.append(p.lerp(q, dp / (dp - dq)))
	return out


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(poly.size()):
		s += poly[i].cross(poly[(i + 1) % poly.size()])
	return s * 0.5


static func _in_hole(holes: Array, p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	for h: Dictionary in holes:
		var a: Vector2 = h["a"]
		var b: Vector2 = h["b"]
		var ab := b - a
		var l2 := ab.length_squared()
		if l2 == 0.0:
			continue
		var t := (q - a).dot(ab) / l2
		if t < 0.0 or t > 1.0:
			continue
		if q.distance_to(a + ab * t) <= float(h["half"]):
			return true
	return false


static func _normals(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.ZERO)
	for t in range(0, indices.size(), 3):
		var a := verts[indices[t]]
		var b := verts[indices[t + 1]]
		var c := verts[indices[t + 2]]
		var n := (c - a).cross(b - a)  # clockwise front face -> outward normal
		normals[indices[t]] += n
		normals[indices[t + 1]] += n
		normals[indices[t + 2]] += n
	for i in range(normals.size()):
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 0.0 else Vector3.UP
	return normals
