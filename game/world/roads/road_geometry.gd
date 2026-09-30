class_name RoadGeometry
extends RefCounted
## Pure geometry helpers for road meshes: polyline cutting, chunk splitting,
## miter normals, and Douglas-Peucker simplification. All static, no state.

const CHUNK_SIZE_M := 256.0
const MITER_LIMIT := 2.0


## Length of a polyline in the xz plane.
static func length_xz(pl: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(pl.size() - 1):
		total += Vector2(pl[i].x, pl[i].z).distance_to(Vector2(pl[i + 1].x, pl[i + 1].z))
	return total


## Point at a distance along the polyline (xz distance), interpolating y.
static func point_at(pl: PackedVector3Array, distance: float) -> Vector3:
	var remaining := distance
	for i in range(pl.size() - 1):
		var seg := Vector2(pl[i + 1].x - pl[i].x, pl[i + 1].z - pl[i].z).length()
		if remaining <= seg or i == pl.size() - 2:
			var t := clampf(remaining / seg, 0.0, 1.0) if seg > 0.0 else 0.0
			return pl[i].lerp(pl[i + 1], t)
		remaining -= seg
	return pl[pl.size() - 1]


## Removes `start` metres from the beginning and `end` metres from the end.
## Returns an empty array if nothing would remain.
static func trim(pl: PackedVector3Array, start: float, end: float) -> PackedVector3Array:
	var total := length_xz(pl)
	if start + end >= total - 0.05:
		return PackedVector3Array()
	var out := PackedVector3Array()
	var walked := 0.0
	var started := false
	for i in range(pl.size() - 1):
		var a := pl[i]
		var b := pl[i + 1]
		var seg := Vector2(b.x - a.x, b.z - a.z).length()
		var seg_start := walked
		var seg_end := walked + seg
		if not started and seg_end > start:
			var t := (start - seg_start) / seg if seg > 0.0 else 0.0
			out.append(a.lerp(b, clampf(t, 0.0, 1.0)))
			started = true
		if started:
			if seg_end >= total - end:
				var t2 := ((total - end) - seg_start) / seg if seg > 0.0 else 1.0
				var last := a.lerp(b, clampf(t2, 0.0, 1.0))
				if out.size() == 0 or last.distance_squared_to(out[out.size() - 1]) > 1e-6:
					out.append(last)
				break
			if b.distance_squared_to(out[out.size() - 1]) > 1e-6:
				out.append(b)
		walked = seg_end
	return out


## Chunk coordinate of a position.
static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CHUNK_SIZE_M)), int(floor(p.z / CHUNK_SIZE_M)))


## Inserts vertices where the polyline crosses chunk boundaries so that every
## segment lies in exactly one chunk. Shared boundary points are bit-identical.
static func split_at_chunk_bounds(pl: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pl.size() == 0:
		return out
	out.append(pl[0])
	for i in range(pl.size() - 1):
		var a := pl[i]
		var b := pl[i + 1]
		var ts: Array[float] = []
		for axis in [0, 2]:
			var va := a[axis]
			var vb := b[axis]
			if va == vb:
				continue
			var lo := minf(va, vb)
			var hi := maxf(va, vb)
			var k := int(floor(lo / CHUNK_SIZE_M)) + 1
			while k * CHUNK_SIZE_M < hi:
				var boundary := k * CHUNK_SIZE_M
				if boundary > lo:
					ts.append((boundary - va) / (vb - va))
				k += 1
		ts.sort()
		for t in ts:
			if t > 1e-6 and t < 1.0 - 1e-6:
				var p := a.lerp(b, t)
				if p.distance_squared_to(out[out.size() - 1]) > 1e-8:
					out.append(p)
		if b.distance_squared_to(out[out.size() - 1]) > 1e-8:
			out.append(b)
	return out


## Chunk that a segment belongs to, decided by its midpoint.
static func chunk_of_segment(a: Vector3, b: Vector3) -> Vector2i:
	return chunk_of((a + b) * 0.5)


## Per-vertex unit normals (xz) for a polyline, mitered at interior vertices.
## `dir_start` and `dir_end` optionally give the direction of the road beyond
## the ends (toward the polyline) so joins at pass-through nodes are seamless.
static func miter_normals(pl: PackedVector3Array, dir_start: Vector2 = Vector2.ZERO, dir_end: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var n := pl.size()
	var normals := PackedVector2Array()
	normals.resize(n)
	var seg_dirs: Array[Vector2] = []
	for i in range(n - 1):
		var d := Vector2(pl[i + 1].x - pl[i].x, pl[i + 1].z - pl[i].z)
		seg_dirs.append(d.normalized() if d.length_squared() > 0.0 else Vector2.RIGHT)
	for i in range(n):
		var d_in: Vector2 = dir_start if i == 0 else seg_dirs[i - 1]
		var d_out: Vector2 = dir_end if i == n - 1 else seg_dirs[i]
		if i == 0 and dir_start == Vector2.ZERO:
			d_in = d_out
		if i == n - 1 and dir_end == Vector2.ZERO:
			d_out = d_in
		var n_in := Vector2(-d_in.y, d_in.x)
		var n_out := Vector2(-d_out.y, d_out.x)
		var m := (n_in + n_out)
		if m.length_squared() < 1e-9:
			normals[i] = n_out
			continue
		m = m.normalized()
		var cos_half := m.dot(n_out)
		var scale := 1.0 / maxf(cos_half, 1.0 / MITER_LIMIT)
		normals[i] = m * scale
	return normals


## Douglas-Peucker simplification in xz with the given tolerance in metres.
static func simplify(pl: PackedVector3Array, tolerance: float) -> PackedVector3Array:
	if pl.size() <= 2:
		return pl.duplicate()
	var keep := PackedByteArray()
	keep.resize(pl.size())
	keep.fill(0)
	keep[0] = 1
	keep[pl.size() - 1] = 1
	_dp(pl, 0, pl.size() - 1, tolerance, keep)
	var out := PackedVector3Array()
	for i in range(pl.size()):
		if keep[i] == 1:
			out.append(pl[i])
	return out


static func _dp(pl: PackedVector3Array, first: int, last: int, tol: float, keep: PackedByteArray) -> void:
	if last <= first + 1:
		return
	var a := Vector2(pl[first].x, pl[first].z)
	var b := Vector2(pl[last].x, pl[last].z)
	var best := -1.0
	var best_i := -1
	for i in range(first + 1, last):
		var p := Vector2(pl[i].x, pl[i].z)
		var d := _point_segment_distance(p, a, b)
		if d > best:
			best = d
			best_i = i
	if best > tol:
		keep[best_i] = 1
		_dp(pl, first, best_i, tol, keep)
		_dp(pl, best_i, last, tol, keep)


static func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 == 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Inserts extra vertices so no segment is longer than `max_len` within `zone` metres of either end.
static func densify_ends(pl: PackedVector3Array, zone: float, max_len: float) -> PackedVector3Array:
	var total := length_xz(pl)
	var out := PackedVector3Array()
	var walked := 0.0
	for i in range(pl.size() - 1):
		var a := pl[i]
		var b := pl[i + 1]
		var seg := Vector2(b.x - a.x, b.z - a.z).length()
		out.append(a)
		var near_end := walked < zone or total - (walked + seg) < zone
		if near_end and seg > max_len:
			var steps := int(ceil(seg / max_len))
			for k in range(1, steps):
				out.append(a.lerp(b, float(k) / steps))
		walked += seg
	out.append(pl[pl.size() - 1])
	return out
