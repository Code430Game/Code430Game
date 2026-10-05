class_name ParkingLotBuilder
extends RefCounted
## Surface parking lots from parking.v0.json: asphalt draped over the terrain, a low kerb round
## the edge, stall markings, curb stops and an entrance sign.
##
## Approach: stalls are laid out once at load (they don't depend on height), along each aisle
## inside the lot on both sides, or along one virtual aisle through the lot's middle when it
## has none, and kept only where the whole stall lies inside the lot, clear of other aisles and
## other stalls. Per chunk, the lot polygon is clipped against every 4 m terrain cell and each
## piece is triangulated at the terrain's own heights, so the asphalt follows the ground the
## car drives on with no gap or step. Multi-storey, underground and rooftop lots are skipped
## (the first are buildings already). Parked cars (ParkedCars) fill the same stalls.

const LIFT_M := 0.05  # asphalt above the terrain
const MARK_LIFT_M := 0.07
const STALL_W_M := 2.6
const STALL_D_M := 5.5
const PARALLEL_W_M := 6.5
const PARALLEL_D_M := 2.2
const DIAGONAL_STEP_M := 3.7  # along the aisle between 45 degree stalls
const LINE_W_M := 0.12
const KERB_W_M := 0.25
const KERB_H_M := 0.1
const AISLE_HALF_DEFAULT_M := 2.75
const EDGE_CLEAR_M := 0.3  # a stall's corners must be this far inside the lot
const ASPHALT := Color(0.33, 0.33, 0.34)  # close to the aisle roads drawn over it
const KERB := Color(0.55, 0.55, 0.53)
const CURB_STOP := Color(0.62, 0.6, 0.56)
const LINE := Color(0.92, 0.92, 0.88)
const SIGN_BLUE := Color(0.12, 0.3, 0.62)
const SIGN_POST := Color(0.35, 0.36, 0.38)
const DRAWN_KINDS := ["surface", "street_side"]


class Stall:
	extends RefCounted
	var centre: Vector2  # (x, z)
	var facing: Vector2  # unit: the way a parked car's nose points (away from the aisle)
	var width: float
	var depth: float
	var index: int  # within its lot, stable
	var y: float = NAN  # ground under the stall, set when its chunk builds (NAN until then)


class Lot:
	extends RefCounted
	var id: String
	var kind: String
	var name: String
	var operator: String
	var capacity: int = -1
	var fee: String
	var access: String
	var orientation: String
	var stall_dir: Vector2
	var ground_y: float
	var outer := PackedVector2Array()
	var holes: Array[PackedVector2Array] = []
	var aisles: PackedStringArray
	var entrances := PackedVector3Array()
	var stalls: Array[Stall] = []
	var bounds: Rect2

	## A downtown-style lot: paid or run by someone (parked cars fill it by day).
	func is_commercial() -> bool:
		return fee == "yes" or operator != ""


## Reads parking.v0.json (missing file: no lots) and lays out every drawn lot's stalls.
static func load_lots(pack_dir: String, graph: RoadGraph) -> Array[Lot]:
	var out: Array[Lot] = []
	var path := pack_dir.path_join("parking.v0.json")
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ParkingLotBuilder: cannot read %s" % path)
		return out
	var streets := street_grid(graph)
	for d: Dictionary in data.get("lots", []):
		if not DRAWN_KINDS.has(str(d.get("kind", "surface"))):
			continue
		out.append(lot_from_dict(d, graph, streets))
	return out


const STREET_CELL_M := 64.0


## Street (non-parking) edge segments by 64 m cell: [a, b, half width] in (x, z), so stalls can
## keep off carriageways that a lot's outline overlaps.
static func street_grid(graph: RoadGraph) -> Dictionary:
	var grid := {}
	if graph == null:
		return grid
	for eid in graph.sorted_edge_ids():
		var e: RoadGraph.RoadEdge = graph.edges[eid]
		if e.road_class == "parking":
			continue
		for i in range(e.polyline.size() - 1):
			var a := Vector2(e.polyline[i].x, e.polyline[i].z)
			var b := Vector2(e.polyline[i + 1].x, e.polyline[i + 1].z)
			var seg := [a, b, e.width_m * 0.5]
			var lo := Vector2i(int(floor(minf(a.x, b.x) / STREET_CELL_M)), int(floor(minf(a.y, b.y) / STREET_CELL_M)))
			var hi := Vector2i(int(floor(maxf(a.x, b.x) / STREET_CELL_M)), int(floor(maxf(a.y, b.y) / STREET_CELL_M)))
			for cx in range(lo.x, hi.x + 1):
				for cz in range(lo.y, hi.y + 1):
					var key := Vector2i(cx, cz)
					if not grid.has(key):
						grid[key] = []
					(grid[key] as Array).append(seg)
	return grid


static func lot_from_dict(d: Dictionary, graph: RoadGraph, streets: Dictionary = {}) -> Lot:
	var lot := Lot.new()
	lot.id = str(d["id"])
	lot.kind = str(d.get("kind", "surface"))
	lot.name = str(d["name"]) if d.get("name") != null else ""
	lot.operator = str(d["operator"]) if d.get("operator") != null else ""
	lot.capacity = int(d["capacity"]) if d.get("capacity") != null else -1
	lot.fee = str(d["fee"]) if d.get("fee") != null else ""
	lot.access = str(d["access"]) if d.get("access") != null else ""
	lot.orientation = str(d["orientation"]) if d.get("orientation") != null else "perpendicular"
	var sd: Array = d.get("stall_dir", [1, 0])
	lot.stall_dir = Vector2(float(sd[0]), float(sd[1])).normalized()
	lot.ground_y = float(d.get("ground_y", 0.0))
	var rings: Array = d.get("rings", [])
	for i in range(rings.size()):
		var ring := PackedVector2Array()
		for p: Array in rings[i]:
			ring.append(Vector2(float(p[0]), float(p[1])))
		if i == 0:
			lot.outer = ring
		else:
			lot.holes.append(ring)
	lot.aisles = PackedStringArray(d.get("aisles", []))
	for e: Array in d.get("entrances", []):
		lot.entrances.append(Vector3(float(e[0]), float(e[1]), float(e[2])))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in lot.outer:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	lot.bounds = Rect2(lo, hi - lo)
	lot.stalls = layout_stalls(lot, graph, streets)
	return lot


## True when `p` is inside the lot (outer ring, not in a hole).
static func contains(lot: Lot, p: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(p, lot.outer):
		return false
	for h in lot.holes:
		if Geometry2D.is_point_in_polygon(p, h):
			return false
	return true


## Distance from `p` to the lot's outline (outer ring and holes).
static func edge_distance(lot: Lot, p: Vector2) -> float:
	var best := INF
	for ring: PackedVector2Array in [lot.outer] + lot.holes:
		for i in range(ring.size()):
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## Stall rectangles along the lot's aisles (or one virtual aisle), deterministic.
static func layout_stalls(lot: Lot, graph: RoadGraph, streets: Dictionary = {}) -> Array[Stall]:
	var near_streets: Array = []
	var lo := Vector2i(int(floor(lot.bounds.position.x / STREET_CELL_M)), int(floor(lot.bounds.position.y / STREET_CELL_M)))
	var hi := Vector2i(int(floor(lot.bounds.end.x / STREET_CELL_M)), int(floor(lot.bounds.end.y / STREET_CELL_M)))
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			for seg in streets.get(Vector2i(cx, cz), []):
				if not near_streets.has(seg):
					near_streets.append(seg)
	var aisles: Array = []  # [PackedVector2Array polyline, half width]
	for eid in lot.aisles:
		if graph == null or not graph.edges.has(eid):
			continue
		var e: RoadGraph.RoadEdge = graph.edges[eid]
		var pl := PackedVector2Array()
		for p in e.polyline:
			pl.append(Vector2(p.x, p.z))
		aisles.append([pl, e.width_m * 0.5])
	if aisles.is_empty():
		var row := _row_only(lot, near_streets)
		if not row.is_empty():
			return row  # just a strip of stalls: the aisle is outside the lot
		aisles.append([_virtual_aisle(lot), AISLE_HALF_DEFAULT_M])
	var w := STALL_W_M
	var depth := STALL_D_M
	var step := STALL_W_M
	if lot.orientation == "parallel":
		w = PARALLEL_W_M
		depth = PARALLEL_D_M
		step = PARALLEL_W_M
	elif lot.orientation == "diagonal":
		step = DIAGONAL_STEP_M
	var stalls: Array[Stall] = []
	for aisle: Array in aisles:
		var pl: PackedVector2Array = aisle[0]
		var half: float = aisle[1]
		for i in range(pl.size() - 1):
			var a := pl[i]
			var b := pl[i + 1]
			var seg := b - a
			var length := seg.length()
			if length < step:
				continue
			var d := seg / length
			var n := Vector2(-d.y, d.x)
			var count := int((length - 1.0) / step)
			var start := (length - count * step) * 0.5 + step * 0.5
			for side: float in [-1.0, 1.0]:
				for k in range(count):
					var along := a + d * (start + k * step)
					var facing := n * side
					if lot.orientation == "diagonal":
						facing = (n * side + d).normalized()  # nose-in at 45 degrees, with the flow
					var centre := along + n * side * (half + depth * 0.5)
					var s := Stall.new()
					s.centre = centre
					s.facing = facing
					s.width = w
					s.depth = depth
					if _fits(lot, s, stalls, aisles, aisle) and _clear_of_streets(s, near_streets):
						s.index = stalls.size()
						stalls.append(s)
	if lot.capacity >= 0 and stalls.size() > lot.capacity:
		stalls.resize(lot.capacity)
	return stalls


## Stalls for a lot too shallow for an aisle and a row (the outline covers only the stalls,
## the aisle lies outside it): one row down the middle, as deep as fits. Empty when the lot is
## deep enough for an aisle, or too shallow for a car.
static func _row_only(lot: Lot, near_streets: Array) -> Array[Stall]:
	var out: Array[Stall] = []
	var c := Vector2.ZERO
	for p in lot.outer:
		c += p
	c /= maxf(lot.outer.size(), 1)
	var n := Vector2(-lot.stall_dir.y, lot.stall_dir.x)
	var lo := INF
	var hi := -INF
	var a_lo := INF
	var a_hi := -INF
	for p in lot.outer:
		lo = minf(lo, (p - c).dot(n))
		hi = maxf(hi, (p - c).dot(n))
		a_lo = minf(a_lo, (p - c).dot(lot.stall_dir))
		a_hi = maxf(a_hi, (p - c).dot(lot.stall_dir))
	var deep := hi - lo
	var with_aisle := 2.0 * AISLE_HALF_DEFAULT_M + STALL_D_M + 2.0 * EDGE_CLEAR_M
	if deep >= with_aisle or deep < 4.5 + 2.0 * EDGE_CLEAR_M:
		return out
	var depth := minf(STALL_D_M, deep - 2.0 * EDGE_CLEAR_M - 0.1)
	var mid := c + n * ((lo + hi) * 0.5)
	var count := int((a_hi - a_lo - 1.0) / STALL_W_M)
	var start := a_lo + (a_hi - a_lo - count * STALL_W_M) * 0.5 + STALL_W_M * 0.5
	for k in range(count):
		var s := Stall.new()
		s.centre = mid + lot.stall_dir * (start + k * STALL_W_M)
		s.facing = n
		s.width = STALL_W_M
		s.depth = depth
		if _fits(lot, s, out, [], []) and _clear_of_streets(s, near_streets):
			s.index = out.size()
			out.append(s)
	if lot.capacity >= 0 and out.size() > lot.capacity:
		out.resize(lot.capacity)
	return out


## One aisle along `stall_dir`: through the middle when two rows of stalls fit across the lot,
## else along one side so a single row fits (most small lots).
static func _virtual_aisle(lot: Lot) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in lot.outer:
		c += p
	c /= maxf(lot.outer.size(), 1)
	var n := Vector2(-lot.stall_dir.y, lot.stall_dir.x)
	var lo := INF
	var hi := -INF
	for p in lot.outer:
		lo = minf(lo, (p - c).dot(n))
		hi = maxf(hi, (p - c).dot(n))
	var two_rows := 2.0 * (AISLE_HALF_DEFAULT_M + STALL_D_M) + 2.0 * EDGE_CLEAR_M
	if hi - lo < two_rows:
		c += n * (lo + AISLE_HALF_DEFAULT_M + EDGE_CLEAR_M)  # aisle hugs one side; one row beside it
	else:
		c += n * ((lo + hi) * 0.5)
	var reach := lot.bounds.size.length()
	var a := c - lot.stall_dir * reach
	var b := c + lot.stall_dir * reach
	# Trim to the stretch inside the lot.
	var hits: Array[float] = []
	for i in range(lot.outer.size()):
		var p: Variant = Geometry2D.segment_intersects_segment(a, b, lot.outer[i], lot.outer[(i + 1) % lot.outer.size()])
		if p != null:
			hits.append((p as Vector2).distance_to(a))
	if hits.size() >= 2:
		hits.sort()
		return PackedVector2Array([a + lot.stall_dir * hits[0], a + lot.stall_dir * hits[hits.size() - 1]])
	return PackedVector2Array([c - lot.stall_dir * 5.0, c + lot.stall_dir * 5.0])


static func stall_corners(s: Stall) -> PackedVector2Array:
	var f := s.facing * s.depth * 0.5
	var r := Vector2(-s.facing.y, s.facing.x) * s.width * 0.5
	return PackedVector2Array([s.centre - f - r, s.centre - f + r, s.centre + f + r, s.centre + f - r])


## False when any corner or the middle of the stall lies on a street's carriageway.
static func _clear_of_streets(s: Stall, streets: Array) -> bool:
	var probes := stall_corners(s)
	probes.append(s.centre)
	for seg: Array in streets:
		var half: float = seg[2]
		for p in probes:
			var q := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
			if q.distance_to(p) < half + 0.3:
				return false
	return true


static func _fits(lot: Lot, s: Stall, placed: Array[Stall], aisles: Array, own: Array) -> bool:
	for c in stall_corners(s):
		if not contains(lot, c) or edge_distance(lot, c) < EDGE_CLEAR_M:
			return false
	for other in placed:
		if other.centre.distance_to(s.centre) < minf(s.width, s.depth) * 0.95:
			return false
	for aisle: Array in aisles:
		if aisle == own:
			continue
		var pl: PackedVector2Array = aisle[0]
		var half: float = aisle[1]
		for i in range(pl.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(s.centre, pl[i], pl[i + 1])
			if q.distance_to(s.centre) < half + minf(s.width, s.depth) * 0.5:
				return false
	return true


## Lots by chunk, for the per-chunk build (a lot crossing a border is in both chunks).
static func by_chunk(lots: Array[Lot], chunk_size: float) -> Dictionary:
	var out := {}
	for lot in lots:
		var c0 := Vector2i(int(floor(lot.bounds.position.x / chunk_size)), int(floor(lot.bounds.position.y / chunk_size)))
		var c1 := Vector2i(int(floor(lot.bounds.end.x / chunk_size)), int(floor(lot.bounds.end.y / chunk_size)))
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var key := Vector2i(cx, cz)
				if not out.has(key):
					out[key] = []
				(out[key] as Array).append(lot)
	return out


## Builds the lots overlapping `coord` on its terrain: {"surface", "markings", "props"}
## ChunkTriangles plus "labels" ([position, basis, text] for the main thread to add).
static func build_chunk(lots: Array, coord: Vector2i, heights: TerrainBuilder.ChunkHeights, chunk_size: float) -> Dictionary:
	var surface := RoadMeshBuilder.ChunkTriangles.new()
	var markings := RoadMeshBuilder.ChunkTriangles.new()
	var props := RoadMeshBuilder.ChunkTriangles.new()
	var labels: Array = []
	var origin := Vector2(coord.x * chunk_size, coord.y * chunk_size)
	var chunk_rect := Rect2(origin, Vector2(chunk_size, chunk_size))
	var res := heights.resolution_m
	for lot: Lot in lots:
		var area := lot.bounds.intersection(chunk_rect)
		if area.size.x <= 0.0 or area.size.y <= 0.0:
			continue
		# Asphalt: the lot clipped to each terrain cell, at the terrain's heights.
		var c0 := Vector2i(int(floor((area.position.x - origin.x) / res)), int(floor((area.position.y - origin.y) / res)))
		var c1 := Vector2i(int(ceil((area.end.x - origin.x) / res)), int(ceil((area.end.y - origin.y) / res)))
		for cz in range(c0.y, c1.y):
			for cx in range(c0.x, c1.x):
				var x0 := origin.x + cx * res
				var z0 := origin.y + cz * res
				var cell := PackedVector2Array([Vector2(x0, z0), Vector2(x0 + res, z0), Vector2(x0 + res, z0 + res), Vector2(x0, z0 + res)])
				for piece in _clip_to_lot(cell, lot):
					_add_flat_polygon(surface, piece, heights, LIFT_M, ASPHALT)
		# Kerb round the edge, the parts in this chunk.
		for ring: PackedVector2Array in [lot.outer] + lot.holes:
			for i in range(ring.size()):
				var a := ring[i]
				var b := ring[(i + 1) % ring.size()]
				var mid := (a + b) * 0.5
				if not chunk_rect.has_point(mid):
					continue
				_add_strip(props, a, b, KERB_W_M, heights, LIFT_M, KERB_H_M, KERB)
		# Stalls whose centres are in this chunk: side lines and a curb stop.
		for s in lot.stalls:
			if not chunk_rect.has_point(s.centre):
				continue
			s.y = heights.sample(s.centre.x, s.centre.y) + LIFT_M  # where a parked car stands
			var r := Vector2(-s.facing.y, s.facing.x)
			var back := s.centre + s.facing * s.depth * 0.5
			var front := s.centre - s.facing * s.depth * 0.5
			for side: float in [-1.0, 1.0]:
				var off := r * s.width * 0.5 * side
				_add_strip(markings, front + off, back + off, LINE_W_M, heights, MARK_LIFT_M, 0.0, LINE)
			var stop := back - s.facing * 0.6
			_add_strip(props, stop - r * 0.8, stop + r * 0.8, 0.2, heights, LIFT_M, 0.15, CURB_STOP)
		# The entrance sign, in the chunk that holds the first entrance.
		if not lot.entrances.is_empty():
			var e := lot.entrances[0]
			if chunk_rect.has_point(Vector2(e.x, e.z)):
				var toward := (lot.bounds.get_center() - Vector2(e.x, e.z)).normalized()
				var spot := Vector2(e.x, e.z) + Vector2(-toward.y, toward.x) * 4.0 + toward * 2.0
				var y := heights.sample(spot.x, spot.y)
				_add_box(props, Vector3(spot.x, y + 1.1, spot.y), Vector3(0.1, 2.2, 0.1), SIGN_POST)
				_add_box(props, Vector3(spot.x, y + 2.4, spot.y), Vector3(0.9, 0.9, 0.08), SIGN_BLUE, toward)
				var text := lot.operator if lot.operator != "" else "P"
				var basis := Basis.looking_at(Vector3(-toward.x, 0.0, -toward.y), Vector3.UP)
				labels.append([Vector3(spot.x, y + 2.4, spot.y) - Vector3(toward.x, 0.0, toward.y) * 0.05, basis, text])
	return {"surface": surface, "markings": markings, "props": props, "labels": labels}


## The parts of a convex cell inside the lot (outer ring minus holes). The clipper returns
## holes wound opposite to their outer polygon; a cell can only get one when a lot hole lies
## wholly inside it (rare at 4 m), and then the cell piece is kept uncut.
static func _clip_to_lot(cell: PackedVector2Array, lot: Lot) -> Array[PackedVector2Array]:
	var cw := Geometry2D.is_polygon_clockwise(cell)
	var pieces: Array[PackedVector2Array] = []
	for p in Geometry2D.intersect_polygons(cell, lot.outer):
		if Geometry2D.is_polygon_clockwise(p) == cw:
			pieces.append(p)
	for h in lot.holes:
		var next: Array[PackedVector2Array] = []
		for piece in pieces:
			var cut := Geometry2D.clip_polygons(piece, h)
			var has_hole := false
			for p in cut:
				if Geometry2D.is_polygon_clockwise(p) != cw:
					has_hole = true
			if has_hole:
				next.append(piece)
			else:
				for p in cut:
					next.append(p)
		pieces = next
	return pieces


static func _add_flat_polygon(tris: RoadMeshBuilder.ChunkTriangles, poly: PackedVector2Array, heights: TerrainBuilder.ChunkHeights, lift: float, color: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for t in range(0, idx.size(), 3):
		var pts: Array[Vector3] = []
		for k in range(3):
			var q := poly[idx[t + k]]
			pts.append(Vector3(q.x, heights.sample(q.x, q.y) + lift, q.y))
		_add_up(tris, pts[0], pts[1], pts[2], color)


## A triangle facing up (Godot front faces are clockwise from the front: the cross product of
## the emitted order points away from the viewer, here down).
static func _add_up(tris: RoadMeshBuilder.ChunkTriangles, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).y > 0.0:
		tris.add_triangle(a, c, b, color)
	else:
		tris.add_triangle(a, b, c, color)


## A strip from a to b (2D), `width` wide, on the terrain; with a height it is a low box.
static func _add_strip(tris: RoadMeshBuilder.ChunkTriangles, a: Vector2, b: Vector2, width: float, heights: TerrainBuilder.ChunkHeights, lift: float, height: float, color: Color) -> void:
	var d := (b - a)
	if d.length() < 0.01:
		return
	var n := Vector2(-d.y, d.x).normalized() * width * 0.5
	var corners := [a - n, b - n, b + n, a + n]
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for c: Vector2 in corners:
		var y := heights.sample(c.x, c.y) + lift
		top.append(Vector3(c.x, y + height, c.y))
		bottom.append(Vector3(c.x, y, c.y))
	_add_up(tris, top[0], top[1], top[2], color)
	_add_up(tris, top[0], top[2], top[3], color)
	if height <= 0.0:
		return
	for i in range(4):
		var j := (i + 1) % 4
		_add_side(tris, bottom[i], bottom[j], top[j], top[i], color)


## An upright quad facing away from the strip's centre line (outward).
static func _add_side(tris: RoadMeshBuilder.ChunkTriangles, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var centre := (a + b + c + d) * 0.25
	var out := Vector3(-(b - a).z, 0.0, (b - a).x)  # one of the two horizontal normals
	var probe := (a + b) * 0.5
	if out.dot(probe - centre) < 0.0:
		out = -out
	# Emit so the cross product points inward (against `out`).
	if (b - a).cross(c - a).dot(out) > 0.0:
		tris.add_triangle(a, c, b, color)
		tris.add_triangle(a, d, c, color)
	else:
		tris.add_triangle(a, b, c, color)
		tris.add_triangle(a, c, d, color)


static func _add_box(tris: RoadMeshBuilder.ChunkTriangles, centre: Vector3, size: Vector3, color: Color, facing: Vector2 = Vector2(0, 1)) -> void:
	var f := Vector3(facing.x, 0.0, facing.y).normalized()
	var r := Vector3(-f.z, 0.0, f.x)
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for sy: float in [-1.0, 1.0]:
		for sf: float in [-1.0, 1.0]:
			for sr: float in [-1.0, 1.0]:
				corners.append(centre + r * h.x * sr + Vector3.UP * h.y * sy + f * h.z * sf)
	# corners index: (sy, sf, sr) bits -> 4*sy + 2*sf + sr
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for q: Array in faces:
		var a: Vector3 = corners[q[0]]
		var b: Vector3 = corners[q[1]]
		var c: Vector3 = corners[q[2]]
		var d: Vector3 = corners[q[3]]
		var face_centre := (a + b + c + d) * 0.25
		var out := face_centre - centre
		if (b - a).cross(c - a).dot(out) > 0.0:
			tris.add_triangle(a, c, b, color)
			tris.add_triangle(a, d, c, color)
		else:
			tris.add_triangle(a, b, c, color)
			tris.add_triangle(a, c, d, color)
