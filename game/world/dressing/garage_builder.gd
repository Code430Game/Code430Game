class_name GarageBuilder
extends RefCounted
## Underground garages from parking.v0.json's `garages` (add-underground-parking).
##
## Every entrance gets a ramp down from the end of its driveway, cut into the terrain (holes,
## like the underpasses), with retaining walls up to the street and a coping that hides the
## cut's ragged edge. A `door` garage ends its ramp at a closed roll-up door in a concrete
## portal. A `garage` garage opens into one level under its footprint: floor, ceiling, walls
## (open where the ramps come in), columns on a grid, light strips and stall lines; its stalls
## become a ParkingLotBuilder.Lot at floor height so ParkedCars fills them like any lot.

const RAMP_WIDTH_M := 6.0
const WALL_M := 0.3
const COPING_M := 3.2  # coping strip past the wall top: covers the 4 m terrain cut's ragged edge
const HOLE_PAD_M := 0.8
const DOOR_W_M := 4.6
const DOOR_H_M := 2.6
const PORTAL_ABOVE_M := 0.9  # portal wall rises this far above the street
const CELL_M := 2.0  # ceiling cells
const COLUMN_HALF_M := 0.3
const LIGHT_GRID_M := 8.0
const STALL_WIDTH_M := 2.6
const STALL_DEPTH_M := 5.3
const AISLE_M := 6.5
const LANDING_M := 12.0  # kept clear past a ramp's foot: room to drive off it and turn into an aisle
const MODULE_M := STALL_DEPTH_M * 2.0 + AISLE_M  # one aisle with a row of stalls each side
const FLOOR_COLOR := Color(0.33, 0.33, 0.33)
const WALL_COLOR := Color(0.55, 0.55, 0.53)
const CEILING_COLOR := Color(0.42, 0.42, 0.41)
const COLUMN_COLOR := Color(0.6, 0.6, 0.58)
const DOOR_COLOR := Color(0.36, 0.38, 0.4)
const SLAT_COLOR := Color(0.3, 0.32, 0.34)
const LINE_COLOR := Color(0.85, 0.85, 0.8)
const LIGHT_COLOR := Color(1.0, 0.97, 0.88)


class Ramp:
	extends RefCounted
	var start: Vector3  # at the street, the driveway's end
	var end: Vector3  # at the garage floor or the door
	var dir: Vector2


class Garage:
	extends RefCounted
	var id: String
	var tier: String  # "door" | "garage"
	var name: String
	var floor_y: float
	var ceiling_y: float
	var outer := PackedVector2Array()
	var ramps: Array[Ramp] = []
	var lot: ParkingLotBuilder.Lot  # garage tier only: the stalls, at floor height
	var columns := PackedVector2Array()  # where stall backs meet, every few stalls
	var lights := PackedVector2Array()  # over the aisles


## Reads the garages; garage-tier ones get a Lot with stalls laid out on the floor.
static func load_garages(pack_dir: String, graph: RoadGraph) -> Array[Garage]:
	var out: Array[Garage] = []
	var path := pack_dir.path_join("parking.v0.json")
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for d: Dictionary in data.get("garages", []):
		var g := Garage.new()
		g.id = str(d["id"])
		g.tier = str(d["tier"])
		g.name = str(d["name"]) if d["name"] != null else ""
		g.floor_y = float(d["floor_y"])
		g.ceiling_y = float(d["ceiling_y"])
		var rings: Array = d["rings"]
		if not rings.is_empty():
			for p: Array in rings[0]:
				g.outer.append(Vector2(float(p[0]), float(p[1])))
		for e: Dictionary in d["entrances"]:
			var r := Ramp.new()
			var a: Array = e["ramp"][0]
			var b: Array = e["ramp"][1]
			r.start = Vector3(float(a[0]), float(a[1]), float(a[2]))
			r.end = Vector3(float(b[0]), float(b[1]), float(b[2]))
			r.dir = Vector2(float(e["dir"][0]), float(e["dir"][1])).normalized()
			g.ramps.append(r)
		if g.tier == "garage" and g.outer.size() >= 3:
			g.lot = _lot_for(g, d, graph)
		out.append(g)
	return out


static func _lot_for(g: Garage, d: Dictionary, graph: RoadGraph) -> ParkingLotBuilder.Lot:
	var ring: Array = []
	for p in g.outer:
		ring.append([p.x, p.y])
	var lot := ParkingLotBuilder.lot_from_dict({
		"id": "garage:" + g.id,
		"kind": "underground",
		"name": d["name"],
		"operator": null,
		"capacity": d["capacity"],
		"fee": d["fee"] if d["fee"] != null else "yes",  # garages read as commercial: full by day
		"access": d["access"],
		"orientation": "perpendicular",
		"stall_dir": _long_axis(g.outer),
		"ground_y": g.floor_y,
		"rings": [ring],
		"aisles": [],
		"entrances": [],
	}, graph, {})
	lot.stalls = _layout(g, Vector2(lot.stall_dir))
	return lot


## Garage stalls: drive aisles every MODULE_M across the floor, a row of stalls each side
## facing away from the aisle; a stall is kept when all four corners are inside the floor,
## clear of the walls and the ramps.
static func _layout(g: Garage, along: Vector2) -> Array[ParkingLotBuilder.Stall]:
	var across := Vector2(-along.y, along.x)
	var lo_u := INF
	var hi_u := -INF
	var lo_v := INF
	var hi_v := -INF
	for p in g.outer:
		lo_u = minf(lo_u, p.dot(along))
		hi_u = maxf(hi_u, p.dot(along))
		lo_v = minf(lo_v, p.dot(across))
		hi_v = maxf(hi_v, p.dot(across))
	var out: Array[ParkingLotBuilder.Stall] = []
	var v := lo_v + STALL_DEPTH_M + AISLE_M * 0.5
	while v < hi_v:
		for side: float in [-1.0, 1.0]:
			var cv := v + side * (AISLE_M * 0.5 + STALL_DEPTH_M * 0.5)
			var u := lo_u + STALL_WIDTH_M * 0.5
			while u < hi_u:
				var s := ParkingLotBuilder.Stall.new()
				s.centre = along * u + across * cv
				s.facing = across * side
				s.width = STALL_WIDTH_M
				s.depth = STALL_DEPTH_M
				if _stall_fits(g, s):
					s.index = out.size()
					s.y = g.floor_y + 0.02
					out.append(s)
				u += STALL_WIDTH_M
		# Lights down the aisle; columns on the line where this aisle's back row meets the next.
		var lu := lo_u + LIGHT_GRID_M * 0.5
		while lu < hi_u:
			_keep_point(g, g.lights, along * lu + across * v, 1.0)
			lu += LIGHT_GRID_M
		var back_v := v + MODULE_M * 0.5
		var cu := lo_u + STALL_WIDTH_M * 3.0
		while cu < hi_u:
			_keep_point(g, g.columns, along * cu + across * back_v, 1.0)
			cu += STALL_WIDTH_M * 3.0
		v += MODULE_M
	return out


static func _keep_point(g: Garage, into: PackedVector2Array, p: Vector2, clearance: float) -> void:
	if Geometry2D.is_point_in_polygon(p, g.outer) and _clear_of_edges(p, g.outer, clearance) and not _near_ramp(g, p, RAMP_WIDTH_M * 0.5 + 1.5, true):
		into.append(p)


static func _stall_fits(g: Garage, s: ParkingLotBuilder.Stall) -> bool:
	for c in ParkingLotBuilder.stall_corners(s):
		if not Geometry2D.is_point_in_polygon(c, g.outer) or not _clear_of_edges(c, g.outer, 0.4):
			return false
	return not _near_ramp(g, s.centre, RAMP_WIDTH_M * 0.5 + STALL_DEPTH_M * 0.5 + 0.5, true)


static func _long_axis(poly: PackedVector2Array) -> Array:
	var best := Vector2.RIGHT
	var best_len := 0.0
	for i in range(poly.size()):
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() > best_len:
			best_len = e.length()
			best = e.normalized()
	return [best.x, best.y]


## True within `reach` of a ramp. With `landing`, also of the strip LANDING_M on past the
## ramp's foot, where a car comes off it onto the floor (issue #60: stalls and columns there
## blocked the way in).
static func _near_ramp(g: Garage, p: Vector2, reach: float, landing: bool = false) -> bool:
	for r in g.ramps:
		var a := Vector2(r.start.x, r.start.z)
		var b := Vector2(r.end.x, r.end.z)
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= reach:
			return true
		if landing and (b - a).length() > 0.01:
			var c := b + (b - a).normalized() * LANDING_M
			if Geometry2D.get_closest_point_to_segment(p, b, c).distance_to(p) <= reach:
				return true
	return false


## Drops surface-lot stalls that would stand on a ramp's cut (a lot outline drawn over the
## driveway put a parked car on top of the portal).
static func clear_ramps(lots: Array[ParkingLotBuilder.Lot], garages: Array[Garage]) -> void:
	var reach := RAMP_WIDTH_M * 0.5 + COPING_M + 1.0
	for lot in lots:
		var near: Array[Garage] = []
		for g in garages:
			for r in g.ramps:
				if lot.bounds.grow(reach).has_point(Vector2(r.start.x, r.start.z)) or lot.bounds.grow(reach).has_point(Vector2(r.end.x, r.end.z)):
					near.append(g)
					break
		if near.is_empty():
			continue
		var kept: Array[ParkingLotBuilder.Stall] = []
		for s in lot.stalls:
			var clear := true
			for g in near:
				if _near_ramp(g, s.centre, reach + s.depth * 0.5):
					clear = false
					break
			if clear:
				s.index = kept.size()
				kept.append(s)
		lot.stalls = kept


## chunk -> [{"a", "b", "half"}]: the terrain cut over each ramp.
static func holes_by_chunk(garages: Array[Garage]) -> Dictionary:
	var out := {}
	for g in garages:
		for r in g.ramps:
			var half := RAMP_WIDTH_M * 0.5 + HOLE_PAD_M
			var hole := {"a": Vector2(r.start.x, r.start.z), "b": Vector2(r.end.x, r.end.z), "half": half}
			var lo := RoadGeometry.chunk_of(Vector3(minf(r.start.x, r.end.x) - half, 0.0, minf(r.start.z, r.end.z) - half))
			var hi := RoadGeometry.chunk_of(Vector3(maxf(r.start.x, r.end.x) + half, 0.0, maxf(r.start.z, r.end.z) + half))
			for cx in range(lo.x, hi.x + 1):
				for cz in range(lo.y, hi.y + 1):
					var key := Vector2i(cx, cz)
					if not out.has(key):
						out[key] = []
					(out[key] as Array).append(hole)
	return out


## {"structure": chunk -> ChunkTriangles, "lights": chunk -> ChunkTriangles}
static func build(garages: Array[Garage]) -> Dictionary:
	var structure := {}
	var lights := {}
	for g in garages:
		for r in g.ramps:
			var out := _bucket(structure, (r.start + r.end) * 0.5)
			_ramp(out, r)
			if g.tier == "door":
				_door(out, r)
		if g.tier == "garage" and g.outer.size() >= 3:
			_box(structure, lights, g)
	return {"structure": structure, "lights": lights}


static func _bucket(buckets: Dictionary, p: Vector3) -> RoadMeshBuilder.ChunkTriangles:
	var c := RoadGeometry.chunk_of(p)
	if not buckets.has(c):
		buckets[c] = RoadMeshBuilder.ChunkTriangles.new()
	return buckets[c]


static func _quad(out: RoadMeshBuilder.ChunkTriangles, p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3, outward: Vector3, color: Color) -> void:
	BarrierBuilder._quad_facing(out, p0, p1, q0, q1, outward, color)


## Ramp floor, retaining walls (inner face, top, coping) from the floor up past the street.
static func _ramp(out: RoadMeshBuilder.ChunkTriangles, r: Ramp) -> void:
	var side := Vector3(-r.dir.y, 0.0, r.dir.x)
	var h := RAMP_WIDTH_M * 0.5
	var top_y := r.start.y + 0.25
	var s0 := r.start - side * h
	var s1 := r.start + side * h
	var e0 := r.end - side * h
	var e1 := r.end + side * h
	_quad(out, s0, s1, e0, e1, Vector3.UP, FLOOR_COLOR)
	for sgn: float in [-1.0, 1.0]:
		var a := r.start + side * (h * sgn)
		var b := r.end + side * (h * sgn)
		var a_top := Vector3(a.x, top_y, a.z)
		var b_top := Vector3(b.x, top_y, b.z)
		var inward := -side * sgn
		_quad(out, a, a_top, b, b_top, inward, WALL_COLOR)  # inner face
		var off := side * (WALL_M * sgn)
		_quad(out, a_top, a_top + off, b_top, b_top + off, Vector3.UP, WALL_COLOR)  # wall top
		var cope := side * (COPING_M * sgn)
		_quad(out, a_top + off, a_top + off + cope, b_top + off, b_top + off + cope, Vector3.UP, WALL_COLOR)


## The closed door at the ramp's foot, in a portal wall that rises past the street.
static func _door(out: RoadMeshBuilder.ChunkTriangles, r: Ramp) -> void:
	var along := Vector3(r.dir.x, 0.0, r.dir.y)
	var side := Vector3(-r.dir.y, 0.0, r.dir.x)
	var hw := RAMP_WIDTH_M * 0.5 + WALL_M
	var base := r.end
	var top := r.start.y + PORTAL_ABOVE_M
	var l := base - side * hw
	var rr := base + side * hw
	_quad(out, l, Vector3(l.x, top, l.z), rr, Vector3(rr.x, top, rr.z), -along, WALL_COLOR)
	# Door panel just proud of the wall, with darker slats.
	var dh := DOOR_W_M * 0.5
	var front := base - along * 0.05
	var d0 := front - side * dh
	var d1 := front + side * dh
	_quad(out, d0, d0 + Vector3(0, DOOR_H_M, 0), d1, d1 + Vector3(0, DOOR_H_M, 0), -along, DOOR_COLOR)
	for k in range(1, 9):
		var y := DOOR_H_M * k / 9.0
		var t0 := front - along * 0.01 - side * dh + Vector3(0, y, 0)
		var t1 := front - along * 0.01 + side * dh + Vector3(0, y, 0)
		_quad(out, t0, t0 + Vector3(0, 0.06, 0), t1, t1 + Vector3(0, 0.06, 0), -along, SLAT_COLOR)


## One level: floor, ceiling cells (open over the ramps), walls (open where ramps enter),
## columns, light strips and stall lines.
static func _box(structure: Dictionary, lights: Dictionary, g: Garage) -> void:
	var poly := g.outer
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		var a := poly[idx[i]]
		var b := poly[idx[i + 1]]
		var c := poly[idx[i + 2]]
		var out := _bucket(structure, Vector3((a.x + b.x + c.x) / 3.0, g.floor_y, (a.y + b.y + c.y) / 3.0))
		_tri_up(out, Vector3(a.x, g.floor_y, a.y), Vector3(b.x, g.floor_y, b.y), Vector3(c.x, g.floor_y, c.y), FLOOR_COLOR)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var x := floorf(lo.x / CELL_M) * CELL_M
	while x < hi.x:
		var z := floorf(lo.y / CELL_M) * CELL_M
		while z < hi.y:
			var centre := Vector2(x + CELL_M * 0.5, z + CELL_M * 0.5)
			if Geometry2D.is_point_in_polygon(centre, poly) and not _near_ramp(g, centre, RAMP_WIDTH_M * 0.5 + 0.2):
				var out := _bucket(structure, Vector3(centre.x, g.ceiling_y, centre.y))
				var y := g.ceiling_y
				_quad(out, Vector3(x, y, z), Vector3(x + CELL_M, y, z), Vector3(x, y, z + CELL_M), Vector3(x + CELL_M, y, z + CELL_M), Vector3.DOWN, CEILING_COLOR)
			z += CELL_M
		x += CELL_M
	# Walls, in pieces of at most CELL_M so the ramp openings are no wider than the ramps.
	var inside_sign := 1.0 if _signed_area(poly) > 0.0 else -1.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := int(ceil(a.distance_to(b) / CELL_M))
		var edge := (b - a).normalized()
		var inward2 := Vector2(-edge.y, edge.x) * inside_sign
		for k in range(n):
			var p := a.lerp(b, float(k) / n)
			var q := a.lerp(b, float(k + 1) / n)
			if _near_ramp(g, (p + q) * 0.5, RAMP_WIDTH_M * 0.5 + 0.5):
				continue
			var out := _bucket(structure, Vector3(p.x, g.floor_y, p.y))
			var p0 := Vector3(p.x, g.floor_y, p.y)
			var q0 := Vector3(q.x, g.floor_y, q.y)
			var up := Vector3(0, g.ceiling_y - g.floor_y, 0)
			_quad(out, p0, p0 + up, q0, q0 + up, Vector3(inward2.x, 0, inward2.y), WALL_COLOR)
	# Light strips over the aisles, columns where the stall backs meet.
	for c in g.lights:
		var light := _bucket(lights, Vector3(c.x, g.ceiling_y, c.y))
		var ly := g.ceiling_y - 0.03
		_quad(light, Vector3(c.x - 0.15, ly, c.y - 1.5), Vector3(c.x + 0.15, ly, c.y - 1.5), Vector3(c.x - 0.15, ly, c.y + 1.5), Vector3(c.x + 0.15, ly, c.y + 1.5), Vector3.DOWN, LIGHT_COLOR)
	for c in g.columns:
		BridgeBuilder._box(_bucket(structure, Vector3(c.x, g.floor_y, c.y)), Vector3(c.x, g.ceiling_y, c.y), Vector3.RIGHT, Vector3.BACK, COLUMN_HALF_M, COLUMN_HALF_M, g.ceiling_y - g.floor_y, COLUMN_COLOR)
	if g.lot != null:
		for s in g.lot.stalls:
			var out := _bucket(structure, Vector3(s.centre.x, g.floor_y, s.centre.y))
			var r := Vector2(-s.facing.y, s.facing.x)
			var back := s.centre + s.facing * s.depth * 0.5
			var front := s.centre - s.facing * s.depth * 0.5
			for sgn: float in [-1.0, 1.0]:
				var off := r * s.width * 0.5 * sgn
				var a := front + off
				var b := back + off
				var w := r * 0.06
				var y := g.floor_y + 0.01
				_quad(out, Vector3(a.x - w.x, y, a.y - w.y), Vector3(a.x + w.x, y, a.y + w.y), Vector3(b.x - w.x, y, b.y - w.y), Vector3(b.x + w.x, y, b.y + w.y), Vector3.UP, LINE_COLOR)


## One triangle wound to face up (Godot's front: (c - a) x (b - a) for (a, b, c)).
static func _tri_up(out: RoadMeshBuilder.ChunkTriangles, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	if (c - a).cross(b - a).y >= 0.0:
		out.add_triangle(a, b, c, color)
	else:
		out.add_triangle(a, c, b, color)


static func _signed_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


static func _clear_of_edges(p: Vector2, poly: PackedVector2Array, reach: float) -> bool:
	for i in range(poly.size()):
		if Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p) < reach:
			return false
	return true


## Vertex-coloured concrete with a faint glow: under a ceiling the sun and most of the sky
## light never reach, and without it the level read near black.
static func material() -> StandardMaterial3D:
	var m := BarrierBuilder.material()
	m.emission_enabled = true
	m.emission = Color(0.55, 0.55, 0.52)
	m.emission_energy_multiplier = 0.25
	return m


static func light_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = LIGHT_COLOR
	m.emission_enabled = true
	m.emission = LIGHT_COLOR
	m.emission_energy_multiplier = 2.0
	return m
