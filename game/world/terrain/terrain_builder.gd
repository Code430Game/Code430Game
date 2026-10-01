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
## (not beyond its ends: the approach cuttings keep their ground).
static func build_mesh(ch: ChunkHeights, lod: int, holes: Array = []) -> ArrayMesh:
	var step: int = LOD_STEPS[lod]
	var n := (ch.samples - 1) / step + 1
	var x0 := ch.cx * (ch.samples - 1) * ch.resolution_m
	var z0 := ch.cz * (ch.samples - 1) * ch.resolution_m
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
	for r in range(n - 1):
		for c in range(n - 1):
			var i0 := r * n + c
			var i1 := i0 + 1
			var i2 := i0 + n
			var i3 := i2 + 1
			if not holes.is_empty() and _in_hole(holes, (verts[i0] + verts[i3]) * 0.5):
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
