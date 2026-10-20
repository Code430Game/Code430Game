class_name YardBuilder
extends RefCounted
## Yards from yards.v0.json (update-houses-and-yards): mown lawns draped over the terrain, a
## concrete path from each door, hedges or shrubs along some front lawns, and wood fences where
## two backyards meet.
##
## Approach: as with parking lots, each lawn is clipped against every 4 m terrain cell of the
## chunk and triangulated at the terrain's own heights, so it lies on the ground with no gap.
## Fences are panels between posts, built into one mesh per chunk (one draw, and it survives the
## GLB chunk cache, which keeps plain meshes only); hedges join that mesh, and both collide.
## A fence or hedge is built in the chunk holding its segment's middle; everything is LOD0 only.

const LAWN_LIFT_M := 0.03
const PATH_LIFT_M := 0.05
const PATH_W_M := 1.1
const FENCE_H_M := 1.6
const FENCE_T_M := 0.06
const FENCE_POST_M := 0.1
const FENCE_PANEL_M := 2.4  # posts at most this far apart
const HEDGE_H_M := 0.9
const HEDGE_W_M := 0.6
const HEDGE_GAP_M := 1.2  # each side of the path where it crosses the frontage
const HEDGE_SHARE := 0.35  # of front lawns with a hedge; the rest get a pair of shrubs by the door
const SHRUB_M := 0.8
const FRONT_LAWN := Color(0.36, 0.47, 0.27)
const BACK_LAWN := Color(0.34, 0.44, 0.26)
const SIDE_LAWN := Color(0.33, 0.42, 0.26)
const PATH := Color(0.68, 0.66, 0.62)
const FENCE := Color(0.55, 0.42, 0.3)
const FENCE_POST := Color(0.45, 0.34, 0.24)
const HEDGE := Color(0.2, 0.33, 0.17)
const VISIBLE_TO_M := 400.0


class Area:
	extends RefCounted
	var outer := PackedVector2Array()
	var holes: Array[PackedVector2Array] = []
	var color: Color
	var bounds: Rect2


class Yard:
	extends RefCounted
	var house: String
	var areas: Array[Area] = []
	var path := PackedVector2Array()  # door, lawn edge; empty: none
	var frontage: Array[PackedVector2Array] = []
	var bounds: Rect2

	## A hedge along the frontage (else shrubs by the door), seeded by the house id.
	func has_hedge() -> bool:
		return float(hash(house + ":hedge") % 1000) / 1000.0 < HEDGE_SHARE


## {"yards": Array[Yard], "fences": Array[PackedVector2Array]}; empty lists when the pack has no
## yards.v0.json.
static func load_yards(pack_dir: String) -> Dictionary:
	var yards: Array[Yard] = []
	var fences: Array[PackedVector2Array] = []
	var path := pack_dir.path_join("yards.v0.json")
	if not FileAccess.file_exists(path):
		return {"yards": yards, "fences": fences}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("YardBuilder: cannot read %s" % path)
		return {"yards": yards, "fences": fences}
	for d: Dictionary in data.get("yards", []):
		yards.append(yard_from_dict(d))
	for f: Dictionary in data.get("fences", []):
		fences.append(_points(f.get("points", [])))
	return {"yards": yards, "fences": fences}


static func yard_from_dict(d: Dictionary) -> Yard:
	var y := Yard.new()
	y.house = str(d.get("house", ""))
	for key: String in ["front", "back", "side"]:
		var color: Color = {"front": FRONT_LAWN, "back": BACK_LAWN, "side": SIDE_LAWN}[key]
		for poly: Array in d.get(key, []):
			var a := Area.new()
			a.color = color
			for i in range(poly.size()):
				var ring := _points(poly[i])
				if i == 0:
					a.outer = ring
				else:
					a.holes.append(ring)
			a.bounds = _bounds(a.outer)
			y.areas.append(a)
			y.bounds = a.bounds if y.bounds.size == Vector2.ZERO else y.bounds.merge(a.bounds)
	y.path = _points(d.get("path", []))
	for line: Array in d.get("frontage", []):
		y.frontage.append(_points(line))
	return y


static func _points(list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in list:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func _bounds(ring: PackedVector2Array) -> Rect2:
	if ring.is_empty():
		return Rect2()
	var r := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		r = r.expand(p)
	return r


## {Vector2i -> {"yards": [...], "fences": [...]}} for the chunks each yard overlaps and the
## chunk holding each fence segment's middle.
static func by_chunk(loaded: Dictionary, chunk_size: float) -> Dictionary:
	var out := {}
	for y: Yard in loaded["yards"]:
		var c0 := Vector2i(int(floor(y.bounds.position.x / chunk_size)), int(floor(y.bounds.position.y / chunk_size)))
		var c1 := Vector2i(int(floor(y.bounds.end.x / chunk_size)), int(floor(y.bounds.end.y / chunk_size)))
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				_entry(out, Vector2i(cx, cz))["yards"].append(y)
	for line: PackedVector2Array in loaded["fences"]:
		for i in range(line.size() - 1):
			var mid := (line[i] + line[i + 1]) * 0.5
			var key := Vector2i(int(floor(mid.x / chunk_size)), int(floor(mid.y / chunk_size)))
			_entry(out, key)["fences"].append(PackedVector2Array([line[i], line[i + 1]]))
	return out


static func _entry(out: Dictionary, key: Vector2i) -> Dictionary:
	if not out.has(key):
		out[key] = {"yards": [], "fences": []}
	return out[key]


## Builds one chunk's yards on its terrain: {"lawns": ChunkTriangles (lawns and paths),
## "props": ChunkTriangles (fences, hedges, shrubs; these collide)}.
static func build_chunk(entry: Dictionary, coord: Vector2i, heights: TerrainBuilder.ChunkHeights, chunk_size: float) -> Dictionary:
	var lawns := RoadMeshBuilder.ChunkTriangles.new()
	var props := RoadMeshBuilder.ChunkTriangles.new()
	var origin := Vector2(coord.x * chunk_size, coord.y * chunk_size)
	var chunk_rect := Rect2(origin, Vector2(chunk_size, chunk_size))
	var res := heights.resolution_m
	for y: Yard in entry["yards"]:
		for a in y.areas:
			var area := a.bounds.intersection(chunk_rect)
			if area.size.x <= 0.0 or area.size.y <= 0.0:
				continue
			var c0 := Vector2i(int(floor((area.position.x - origin.x) / res)), int(floor((area.position.y - origin.y) / res)))
			var c1 := Vector2i(int(ceil((area.end.x - origin.x) / res)), int(ceil((area.end.y - origin.y) / res)))
			for cz in range(c0.y, c1.y):
				for cx in range(c0.x, c1.x):
					var x0 := origin.x + cx * res
					var z0 := origin.y + cz * res
					var cell := PackedVector2Array([Vector2(x0, z0), Vector2(x0 + res, z0), Vector2(x0 + res, z0 + res), Vector2(x0, z0 + res)])
					for piece in ParkingLotBuilder.clip_to_rings(cell, a.outer, a.holes):
						ParkingLotBuilder._add_flat_polygon(lawns, piece, heights, LAWN_LIFT_M, a.color)
		# The path, hedges and shrubs belong to the chunk holding the door.
		if y.path.size() == 2 and chunk_rect.has_point(y.path[0]):
			ParkingLotBuilder._add_strip(lawns, y.path[0], y.path[1], PATH_W_M, heights, PATH_LIFT_M, 0.0, PATH)
		var anchor := y.path[0] if y.path.size() == 2 else (y.frontage[0][0] if not y.frontage.is_empty() else Vector2.INF)
		if anchor == Vector2.INF or not chunk_rect.has_point(anchor):
			continue
		if y.has_hedge():
			for line in y.frontage:
				for seg in hedge_segments(line, y.path):
					ParkingLotBuilder._add_strip(props, seg[0], seg[1], HEDGE_W_M, heights, 0.0, HEDGE_H_M, HEDGE)
		elif y.path.size() == 2:
			var d := (y.path[1] - y.path[0]).normalized()
			var side := Vector2(-d.y, d.x)
			for s: float in [-1.0, 1.0]:
				var p := y.path[0] + d * 1.2 + side * s * (PATH_W_M * 0.5 + SHRUB_M * 0.6)
				var g := heights.sample(p.x, p.y)
				ParkingLotBuilder._add_box(props, Vector3(p.x, g + SHRUB_M * 0.5, p.y), Vector3(SHRUB_M, SHRUB_M, SHRUB_M), HEDGE)
	for seg: PackedVector2Array in entry["fences"]:
		_fence(props, seg[0], seg[1], heights)
	return {"lawns": lawns, "props": props}


## A frontage line with the stretch where the path crosses it cut out: [[a, b], ...].
static func hedge_segments(line: PackedVector2Array, path: PackedVector2Array) -> Array:
	var out: Array = []
	var gap := path[1] if path.size() == 2 else Vector2.INF
	for i in range(line.size() - 1):
		var a := line[i]
		var b := line[i + 1]
		var length := a.distance_to(b)
		if length < 0.3:
			continue
		var d := (b - a) / length
		var t := (gap - a).dot(d) if gap != Vector2.INF else -INF
		var off := (gap - (a + d * t)).length() if gap != Vector2.INF else INF
		if off < HEDGE_GAP_M and t > -HEDGE_GAP_M and t < length + HEDGE_GAP_M:
			if t - HEDGE_GAP_M > 0.3:
				out.append([a, a + d * (t - HEDGE_GAP_M)])
			if length - (t + HEDGE_GAP_M) > 0.3:
				out.append([a + d * (t + HEDGE_GAP_M), b])
		else:
			out.append([a, b])
	return out


## Fence panels from a to b, a post at each end and every FENCE_PANEL_M, standing on the
## terrain (each panel at its ends' lower ground, sunk so a slope leaves no gap).
static func _fence(tris: RoadMeshBuilder.ChunkTriangles, a: Vector2, b: Vector2, heights: TerrainBuilder.ChunkHeights) -> void:
	var length := a.distance_to(b)
	if length < 0.2:
		return
	var n := maxi(1, ceili(length / FENCE_PANEL_M))
	var d := (b - a) / length
	for k in range(n):
		var p := a + d * (length * k / n)
		var q := a + d * (length * (k + 1) / n)
		var gp := heights.sample(p.x, p.y)
		var gq := heights.sample(q.x, q.y)
		var low := minf(gp, gq) - 0.1
		var top := maxf(gp, gq) + FENCE_H_M - 0.1
		var mid := (p + q) * 0.5
		var size := Vector3(FENCE_T_M, top - low, (length / n))
		ParkingLotBuilder._add_box(tris, Vector3(mid.x, (low + top) * 0.5, mid.y), size, FENCE, d)
		var gp0 := gp - 0.1
		ParkingLotBuilder._add_box(tris, Vector3(p.x, gp0 + (FENCE_H_M + 0.1) * 0.5, p.y), Vector3(FENCE_POST_M, FENCE_H_M + 0.1, FENCE_POST_M), FENCE_POST, d)
	var gb := heights.sample(b.x, b.y) - 0.1
	ParkingLotBuilder._add_box(tris, Vector3(b.x, gb + (FENCE_H_M + 0.1) * 0.5, b.y), Vector3(FENCE_POST_M, FENCE_H_M + 0.1, FENCE_POST_M), FENCE_POST, d)
