class_name BuildingBuilder
extends RefCounted
## Extrudes building footprints from buildings.v0.json into walls and flat roofs per chunk.
##
## Rings are oriented by the import tool (outer counter-clockwise in x,z, holes
## clockwise), so the outward wall normal of an edge a->b is (dz, -dx) for both.
## Roof triangles come pre-computed (earcut) and already face up under Godot's
## clockwise-front rule, as with water. Walls start `wall_embed_m` below the
## ground height so slopes leave no gap.

const WALL_EMBED_M := 2.0
const LOD1_MIN_HEIGHT_M := 12.0
const LOD1_MIN_AREA_M2 := 300.0
const ROOF_DARKEN := 0.12
## Houses get black asphalt shingles whatever their walls (human, 2026-10-21: "a simple
## improvement is to make all house roofs black shingles"), a little lighter or darker each.
const SHINGLE_COLOR := Color(0.13, 0.13, 0.14)
const SHINGLE_VARIATION := 0.08
const VARIATION := 0.08
const FACADE_SHADER := preload("res://world/buildings/facade.gdshader")
## Facade treatments (see facade.gdshader): 0 plain, 1 punched brick, 2 glass grid, 3 stone,
## 4 stucco, 5 precast, 6 curtain wall. +SHOPFRONT_FLAG marks a shopfront ground floor.
const TREATMENT_PLAIN := 0
const TREATMENT_PUNCHED := 1
const TREATMENT_GLASS := 2
const TREATMENT_STONE := 3
const TREATMENT_STUCCO := 4
const TREATMENT_PRECAST := 5
const TREATMENT_CURTAIN := 6
const SHOPFRONT_FLAG := 10
const TRIM_UV2 := -2.0
const HOUSE_KINDS := ["house", "detached", "semidetached_house", "terrace", "bungalow", "residential"]
const APARTMENT_KINDS := ["apartments", "dormitory", "hotel"]
const PITCHED_MAX_HEIGHT_M := 12.0
const PITCHED_MIN_FILL := 0.8  # footprint area over its oriented box: how rectangular it must be
const PITCHED_MAX_AREA_M2 := 350.0  # bigger "residential" footprints are blocks, not houses
const PITCHED_MAX_HALF_SHORT_M := 9.0
const PARAPET_MIN_HEIGHT_M := 8.0
const PARAPET_H_M := 0.5
const PARAPET_T_M := 0.3
const ROOF_BOX_MIN_HEIGHT_M := 30.0
const SHOPFRONT_MIN_WALL_M := 6.0
const BALCONY_MIN_HEIGHT_M := 12.0
const BALCONY_MIN_WALL_M := 10.0
const BALCONY_DEPTH_M := 1.2
const BALCONY_WIDTH_M := 2.4
const BALCONY_SLAB_M := 0.15
const STOREY_M := 3.2
const NAMED_COLOURS := {
	"white": Color(0.9, 0.9, 0.88), "black": Color(0.12, 0.12, 0.12), "grey": Color(0.55, 0.55, 0.55), "gray": Color(0.55, 0.55, 0.55),
	"red": Color(0.6, 0.2, 0.16), "brown": Color(0.45, 0.32, 0.22), "beige": Color(0.8, 0.72, 0.58), "yellow": Color(0.85, 0.75, 0.35),
	"blue": Color(0.3, 0.42, 0.62), "green": Color(0.35, 0.5, 0.38), "cream": Color(0.9, 0.85, 0.7), "tan": Color(0.76, 0.66, 0.5),
}
const GLASS_MIN_HEIGHT_M := 15.0
const TALL_GLASS_HEIGHT_M := 40.0
const PLAIN_MAX_HEIGHT_M := 3.5
const STONE_KINDS := ["church", "cathedral", "university", "school", "public", "government", "hospital"]
const PLAIN_KINDS := ["garage", "garages", "shed", "roof", "industrial", "warehouse"]
const CANOPY_KINDS := ["roof", "carport"]  # roofs with no walls: open underneath
const CANOPY_THICK_M := 0.4
const CANOPY_MIN_CLEARANCE_M := 2.6
const CANOPY_POST_M := 0.25
const GLASS_KINDS := ["office", "commercial", "retail", "hotel"]

const KIND_COLORS := {
	"house": Color(0.72, 0.62, 0.52),
	"detached": Color(0.72, 0.62, 0.52),
	"semidetached_house": Color(0.70, 0.60, 0.50),
	"terrace": Color(0.66, 0.52, 0.44),
	"residential": Color(0.62, 0.58, 0.54),
	"apartments": Color(0.58, 0.56, 0.54),
	"commercial": Color(0.52, 0.56, 0.62),
	"retail": Color(0.56, 0.58, 0.62),
	"office": Color(0.48, 0.54, 0.62),
	"industrial": Color(0.50, 0.50, 0.48),
	"warehouse": Color(0.50, 0.50, 0.48),
	"garage": Color(0.42, 0.42, 0.42),
	"garages": Color(0.42, 0.42, 0.42),
	"shed": Color(0.40, 0.38, 0.34),
	"church": Color(0.74, 0.70, 0.62),
	"cathedral": Color(0.74, 0.70, 0.62),
	"university": Color(0.66, 0.62, 0.56),
	"school": Color(0.66, 0.62, 0.56),
	"public": Color(0.68, 0.66, 0.60),
	"government": Color(0.68, 0.66, 0.60),
	"hospital": Color(0.70, 0.70, 0.68),
	"hotel": Color(0.60, 0.58, 0.60),
}
const DEFAULT_COLOR := Color(0.60, 0.58, 0.56)


class Building:
	extends RefCounted
	var id: String
	var kind: String
	var name: String
	var material: String = ""
	var colour: String = ""
	var roof_shape: String = ""
	var levels: float = 0.0
	var shopfront: bool = false
	var height_m: float
	var ground_y: float
	var rings: Array[PackedVector2Array] = []
	var roof_vertices: PackedVector2Array
	var roof_triangles: PackedInt32Array

	func centroid() -> Vector2:
		var sum := Vector2.ZERO
		for p in rings[0]:
			sum += p
		return sum / rings[0].size()

	func footprint_area() -> float:
		var a := 0.0
		var r := rings[0]
		for i in range(r.size()):
			var p := r[i]
			var q := r[(i + 1) % r.size()]
			a += p.x * q.y - q.x * p.y
		return absf(a) * 0.5


## Reads buildings.v0.json; returns an empty array when the pack has none.
static func load_buildings(pack_dir: String) -> Array[Building]:
	var out: Array[Building] = []
	var path := pack_dir.path_join("buildings.v0.json")
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BuildingBuilder: bad JSON in %s" % path)
		return out
	for b: Dictionary in parsed.get("buildings", []):
		var bld := Building.new()
		bld.id = b["id"]
		bld.kind = b["kind"]
		bld.name = str(b["name"]) if b["name"] != null else ""
		bld.height_m = float(b["height_m"])
		bld.ground_y = float(b["ground_y"])
		for ring in b["rings"]:
			var pts := PackedVector2Array()
			for v in ring:
				pts.append(Vector2(float(v[0]), float(v[1])))
			bld.rings.append(pts)
		var rv: Array = b["roof_vertices"]
		if rv.is_empty():
			bld.roof_vertices = bld.rings[0]
		else:
			for v in rv:
				bld.roof_vertices.append(Vector2(float(v[0]), float(v[1])))
		for i in b["roof_triangles"]:
			bld.roof_triangles.append(int(i))
		bld.material = str(b.get("material", ""))
		bld.colour = str(b.get("colour", ""))
		bld.roof_shape = str(b.get("roof_shape", ""))
		bld.levels = float(b.get("levels", 0.0))
		bld.shopfront = bool(b.get("shopfront", false))
		out.append(bld)
	return out


## Facade treatment for a building type and height (material and seed refine it, see treatment_of).
static func treatment_for(kind: String, height_m: float) -> int:
	return treatment_of(kind, height_m, "", 0.5)


## Facade treatment from the tagged material first, then kind and height; the seed picks
## between the two plausible looks of a kind so a street of houses is not all one wall.
static func treatment_of(kind: String, height_m: float, material: String, seed: float) -> int:
	if height_m <= PLAIN_MAX_HEIGHT_M or kind in PLAIN_KINDS:
		return TREATMENT_PLAIN
	match material:
		"glass":
			return TREATMENT_CURTAIN
		"brick":
			return TREATMENT_PUNCHED
		"stone", "sandstone", "limestone", "marble":
			return TREATMENT_STONE
		"concrete":
			return TREATMENT_PRECAST if height_m > 12.0 else TREATMENT_STUCCO
		"wood", "vinyl", "plaster", "stucco", "metal":
			return TREATMENT_STUCCO
	if height_m >= TALL_GLASS_HEIGHT_M:
		return TREATMENT_CURTAIN if seed < 0.6 else TREATMENT_GLASS
	if kind in STONE_KINDS:
		return TREATMENT_STONE
	if kind in GLASS_KINDS and height_m >= GLASS_MIN_HEIGHT_M:
		return TREATMENT_GLASS if seed < 0.7 else TREATMENT_PRECAST
	if kind in HOUSE_KINDS:
		return TREATMENT_STUCCO if seed < 0.45 else TREATMENT_PUNCHED
	if kind in APARTMENT_KINDS and height_m >= 12.0:
		return TREATMENT_PRECAST if seed < 0.5 else TREATMENT_PUNCHED
	return TREATMENT_PUNCHED


## Parses an OSM colour: "#rrggbb", "rrggbb" or a few names. Returns Color.TRANSPARENT when unknown.
static func parse_colour(text: String) -> Color:
	var t := text.strip_edges().to_lower()
	if t == "":
		return Color.TRANSPARENT
	if NAMED_COLOURS.has(t):
		return NAMED_COLOURS[t]
	var hex := t.trim_prefix("#")
	if hex.length() == 6 and hex.is_valid_hex_number():
		return Color.html("#" + hex)
	return Color.TRANSPARENT


## Per-building seed in 0..1 from its id.
static func seed_for(id: String) -> float:
	return float(hash(id) % 10007) / 10007.0


## Colour for a building: the tagged colour when present, else the kind colour with a small
## deterministic variation per id.
static func color_for(b: Building) -> Color:
	var tagged := parse_colour(b.colour)
	if tagged != Color.TRANSPARENT:
		return tagged
	var base: Color = KIND_COLORS.get(b.kind, DEFAULT_COLOR)
	var h := float(hash(b.id) % 1000) / 1000.0
	return base.lightened((h - 0.5) * VARIATION) if h >= 0.5 else base.darkened((0.5 - h) * VARIATION)


## A building's roof colour: black shingles on houses, else its walls a little darker.
static func roof_color_for(b: Building, wall: Color) -> Color:
	if b.kind in HOUSE_KINDS:
		var h := float(hash(b.id + ":roof") % 1000) / 1000.0
		return SHINGLE_COLOR.lightened((h - 0.5) * SHINGLE_VARIATION)
	return wall.darkened(ROOF_DARKEN)


## Oriented bounding box of a ring: {"centre", "axis" (unit long axis), "half_long", "half_short", "fill"}.
## Fill is the ring area over the box area: 1 for a rectangle.
static func oriented_box(ring: PackedVector2Array) -> Dictionary:
	var best := {}
	var best_area := INF
	var area := absf(_ring_area(ring))
	for i in range(ring.size()):
		var e := ring[(i + 1) % ring.size()] - ring[i]
		if e.length_squared() < 1e-6:
			continue
		var ax := e.normalized()
		var ay := Vector2(-ax.y, ax.x)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in ring:
			var q := Vector2(p.dot(ax), p.dot(ay))
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		var size := hi - lo
		var box_area := size.x * size.y
		if box_area < best_area:
			best_area = box_area
			var centre_local := (lo + hi) * 0.5
			var long_axis := ax if size.x >= size.y else ay
			best = {
				"centre": ax * centre_local.x + ay * centre_local.y,
				"axis": long_axis,
				"half_long": maxf(size.x, size.y) * 0.5,
				"half_short": minf(size.x, size.y) * 0.5,
				"fill": area / maxf(box_area, 1e-6),
			}
	return best


static func _ring_area(r: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(r.size()):
		var p := r[i]
		var q := r[(i + 1) % r.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Roof style for a building: "gable", "hip" or "flat".
static func roof_style_for(b: Building, box: Dictionary) -> String:
	if b.roof_shape in ["gabled", "gable", "pitched", "saltbox"]:
		return "gable"
	if b.roof_shape in ["hipped", "hip", "pyramidal"]:
		return "hip"
	if b.roof_shape != "":
		return "flat"
	var house_sized := b.footprint_area() <= PITCHED_MAX_AREA_M2 and float(box.get("half_short", 99.0)) <= PITCHED_MAX_HALF_SHORT_M
	if b.kind in HOUSE_KINDS and house_sized and b.height_m <= PITCHED_MAX_HEIGHT_M and b.rings.size() == 1 and float(box.get("fill", 0.0)) >= PITCHED_MIN_FILL:
		return "gable" if seed_for(b.id) < 0.75 else "hip"
	return "flat"


## Builds {"lod0": chunk -> ChunkTriangles, "lod1": chunk -> ChunkTriangles}.
static func build(buildings: Array[Building]) -> Dictionary:
	var lod0 := {}
	var lod1 := {}
	for b in buildings:
		var chunk := RoadGeometry.chunk_of(Vector3(b.centroid().x, 0.0, b.centroid().y))
		if not lod0.has(chunk):
			lod0[chunk] = RoadMeshBuilder.ChunkTriangles.new()
		_extrude(b, lod0[chunk])
		if b.height_m >= LOD1_MIN_HEIGHT_M or b.footprint_area() >= LOD1_MIN_AREA_M2:
			if not lod1.has(chunk):
				lod1[chunk] = RoadMeshBuilder.ChunkTriangles.new()
			_extrude(b, lod1[chunk])
	return {"lod0": lod0, "lod1": lod1}


static func _extrude(b: Building, out: RoadMeshBuilder.ChunkTriangles) -> void:
	if b.kind in CANOPY_KINDS:
		_canopy(b, out)
		return
	var wall := color_for(b)
	var roof := roof_color_for(b, wall)
	var y0 := b.ground_y - WALL_EMBED_M
	var y1 := b.ground_y + b.height_m
	var seed := seed_for(b.id)
	var treatment := treatment_of(b.kind, b.height_m, b.material, seed)
	var base_uv2 := Vector2(float(treatment), seed)
	var roof_uv2 := Vector2(-1.0, seed)
	var trim_uv2 := Vector2(TRIM_UV2, seed)
	var box := oriented_box(b.rings[0]) if not b.rings.is_empty() else {}
	var style := roof_style_for(b, box)
	for ring in b.rings:
		var along := 0.0
		for i in range(ring.size()):
			var a := ring[i]
			var c := ring[(i + 1) % ring.size()]
			if a.distance_squared_to(c) < 1e-6:
				continue
			var d := c - a
			var outward := Vector3(d.y, 0.0, -d.x).normalized()
			var uv2 := base_uv2
			if b.shopfront and d.length() >= SHOPFRONT_MIN_WALL_M and treatment != TREATMENT_PLAIN:
				uv2 = Vector2(float(treatment + SHOPFRONT_FLAG), seed)
			if b.kind in APARTMENT_KINDS and b.height_m >= BALCONY_MIN_HEIGHT_M and d.length() >= BALCONY_MIN_WALL_M and ring == b.rings[0]:
				_balconies(a, c, outward, b.ground_y, b.height_m, wall.darkened(0.2), trim_uv2, out)
			var a_low := Vector3(a.x, y0, a.y)
			var a_high := Vector3(a.x, y1, a.y)
			var c_low := Vector3(c.x, y0, c.y)
			var c_high := Vector3(c.x, y1, c.y)
			var u0 := along
			var u1 := along + d.length()
			along = u1
			# UV: u along the wall in metres, v metres above ground (negative below).
			var ua_low := Vector2(u0, -WALL_EMBED_M)
			var ua_high := Vector2(u0, b.height_m)
			var uc_low := Vector2(u1, -WALL_EMBED_M)
			var uc_high := Vector2(u1, b.height_m)
			# Pick the winding whose front normal (Godot: clockwise front) points outward.
			var n := (c_high - a_low).cross(c_low - a_low)
			if n.dot(outward) >= 0.0:
				out.add_triangle_uv(a_low, c_low, c_high, wall, ua_low, uc_low, uc_high, uv2)
				out.add_triangle_uv(a_low, c_high, a_high, wall, ua_low, uc_high, ua_high, uv2)
			else:
				out.add_triangle_uv(a_low, c_high, c_low, wall, ua_low, uc_high, uc_low, uv2)
				out.add_triangle_uv(a_low, a_high, c_high, wall, ua_low, ua_high, uc_high, uv2)
	for t in range(0, b.roof_triangles.size(), 3):
		var p := b.roof_vertices[b.roof_triangles[t]]
		var q := b.roof_vertices[b.roof_triangles[t + 1]]
		var r := b.roof_vertices[b.roof_triangles[t + 2]]
		out.add_triangle_uv(Vector3(p.x, y1, p.y), Vector3(q.x, y1, q.y), Vector3(r.x, y1, r.y), roof, p, q, r, roof_uv2)
	if style != "flat" and not box.is_empty():
		_pitched_roof(box, y1, style, roof.darkened(0.1), roof_uv2, out)
	elif b.height_m >= PARAPET_MIN_HEIGHT_M and treatment != TREATMENT_CURTAIN and b.kind not in HOUSE_KINDS:
		_parapet(b.rings[0], y1, wall.darkened(0.1), trim_uv2, out)
		if b.height_m >= ROOF_BOX_MIN_HEIGHT_M and not box.is_empty() and float(box["half_short"]) > 6.0:
			var c2: Vector2 = box["centre"]
			_box(Vector3(c2.x, y1 + 1.5, c2.y), Vector3(4.0, 3.0, 3.0), box["axis"], wall.darkened(0.3), trim_uv2, out)


## OSM `building=roof` (and carports) is a roof with no walls: a drop-off canopy, a fuel-station
## roof, a covered walkway. Built as a slab at the top with a fascia round its edge and a thin
## post at each corner, open underneath, so people and cars pass below it; built as a solid
## block from the ground it boxed in the hospital's drop-off and the respawn there (#80).
static func _canopy(b: Building, out: RoadMeshBuilder.ChunkTriangles) -> void:
	var wall := color_for(b)
	var y1 := b.ground_y + maxf(b.height_m, CANOPY_MIN_CLEARANCE_M + CANOPY_THICK_M)
	var y0 := y1 - CANOPY_THICK_M
	var uv2 := Vector2(float(TREATMENT_PLAIN), seed_for(b.id))
	for ring in b.rings:
		for i in range(ring.size()):
			var a := ring[i]
			var c := ring[(i + 1) % ring.size()]
			if a.distance_squared_to(c) < 1e-6:
				continue
			var d := c - a
			var outward := Vector3(d.y, 0.0, -d.x).normalized()
			var a_low := Vector3(a.x, y0, a.y)
			var a_high := Vector3(a.x, y1, a.y)
			var c_low := Vector3(c.x, y0, c.y)
			var c_high := Vector3(c.x, y1, c.y)
			var ua := Vector2(0.0, 0.0)
			var uc := Vector2(d.length(), 0.0)
			var n := (c_high - a_low).cross(c_low - a_low)
			if n.dot(outward) >= 0.0:
				out.add_triangle_uv(a_low, c_low, c_high, wall, ua, uc, uc + Vector2(0, CANOPY_THICK_M), uv2)
				out.add_triangle_uv(a_low, c_high, a_high, wall, ua, uc + Vector2(0, CANOPY_THICK_M), ua + Vector2(0, CANOPY_THICK_M), uv2)
			else:
				out.add_triangle_uv(a_low, c_high, c_low, wall, ua, uc + Vector2(0, CANOPY_THICK_M), uc, uv2)
				out.add_triangle_uv(a_low, a_high, c_high, wall, ua, ua + Vector2(0, CANOPY_THICK_M), uc + Vector2(0, CANOPY_THICK_M), uv2)
		# A post at each corner, from the ground to the slab.
		for i in range(ring.size()):
			var prev := ring[(i - 1 + ring.size()) % ring.size()]
			var here := ring[i]
			var next := ring[(i + 1) % ring.size()]
			var turn := (here - prev).normalized().cross((next - here).normalized())
			if absf(turn) < 0.5:
				continue  # not a corner: the edge only bends a little here
			var inward := ((prev - here).normalized() + (next - here).normalized()).normalized()
			var p := here + inward * CANOPY_POST_M
			var foot := b.ground_y - WALL_EMBED_M
			_box(Vector3(p.x, (y0 + foot) * 0.5, p.y), Vector3(CANOPY_POST_M, y0 - foot, CANOPY_POST_M), Vector2.RIGHT, wall.darkened(0.15), uv2, out)
	var roof := roof_color_for(b, wall)
	var roof_uv2 := Vector2(-1.0, seed_for(b.id))
	for t in range(0, b.roof_triangles.size(), 3):
		var p := b.roof_vertices[b.roof_triangles[t]]
		var q := b.roof_vertices[b.roof_triangles[t + 1]]
		var r := b.roof_vertices[b.roof_triangles[t + 2]]
		out.add_triangle_uv(Vector3(p.x, y1, p.y), Vector3(q.x, y1, q.y), Vector3(r.x, y1, r.y), roof, p, q, r, roof_uv2)
		out.add_triangle_uv(Vector3(p.x, y0, p.y), Vector3(r.x, y0, r.y), Vector3(q.x, y0, q.y), roof.darkened(0.3), p, r, q, roof_uv2)  # the underside


## A gabled or hipped roof over the footprint's oriented box, from the eave at y_eave.
static func _pitched_roof(box: Dictionary, y_eave: float, style: String, color: Color, uv2: Vector2, out: RoadMeshBuilder.ChunkTriangles) -> void:
	var c: Vector2 = box["centre"]
	var ax: Vector2 = box["axis"]
	var ay := Vector2(-ax.y, ax.x)
	var hl: float = box["half_long"]
	var hs: float = box["half_short"]
	var rise := clampf(hs * 0.7, 1.2, 4.5)
	var ridge_y := y_eave + rise
	var inset := hs * 0.9 if style == "hip" else 0.0
	var corners: Array[Vector2] = [c + ax * hl + ay * hs, c + ax * hl - ay * hs, c - ax * hl - ay * hs, c - ax * hl + ay * hs]
	var r0 := c + ax * (hl - inset)
	var r1 := c - ax * (hl - inset)
	var e: Array[Vector3] = []
	for k in corners:
		e.append(Vector3(k.x, y_eave, k.y))
	var ra := Vector3(r0.x, ridge_y, r0.y)
	var rb := Vector3(r1.x, ridge_y, r1.y)
	var centre3 := Vector3(c.x, y_eave, c.y)
	_roof_quad(e[0], e[3], rb, ra, color, uv2, centre3, out)
	_roof_quad(e[2], e[1], ra, rb, color, uv2, centre3, out)
	if style == "hip":
		_roof_tri(e[1], e[0], ra, color, uv2, centre3, out)
		_roof_tri(e[3], e[2], rb, color, uv2, centre3, out)
	else:
		_roof_tri(e[0], e[1], ra, color.lightened(0.1), uv2, centre3, out)
		_roof_tri(e[2], e[3], rb, color.lightened(0.1), uv2, centre3, out)


static func _roof_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, uv2: Vector2, centre: Vector3, out: RoadMeshBuilder.ChunkTriangles) -> void:
	_roof_tri(a, b, c, color, uv2, centre, out)
	_roof_tri(a, c, d, color, uv2, centre, out)


## Triangle wound so its front faces away from the roof's centre (up, or outward for gable ends).
static func _roof_tri(a: Vector3, b: Vector3, c: Vector3, color: Color, uv2: Vector2, centre: Vector3, out: RoadMeshBuilder.ChunkTriangles) -> void:
	var n := (b - a).cross(c - a)
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - centre) > 0.0:
		var t := b
		b = c
		c = t
	out.add_triangle_uv(a, b, c, color, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), uv2)


## A low lip along the roof edge: the ring offset inward and extruded PARAPET_H_M up.
static func _parapet(ring: PackedVector2Array, y: float, color: Color, uv2: Vector2, out: RoadMeshBuilder.ChunkTriangles) -> void:
	for i in range(ring.size()):
		var a := ring[i]
		var c := ring[(i + 1) % ring.size()]
		var d := c - a
		if d.length_squared() < 1e-6:
			continue
		var inward := Vector2(-d.y, d.x).normalized() * PARAPET_T_M
		var a_in := a + inward
		var c_in := c + inward
		_prism(Vector3(a.x, y, a.y), Vector3(c.x, y, c.y), Vector3(c_in.x, y, c_in.y), Vector3(a_in.x, y, a_in.y), PARAPET_H_M, color, uv2, out)


## Balcony slabs every storey along a wall, centred on each 6 m bay.
static func _balconies(a: Vector2, c: Vector2, outward: Vector3, ground_y: float, height_m: float, color: Color, uv2: Vector2, out: RoadMeshBuilder.ChunkTriangles) -> void:
	var d := c - a
	var length := d.length()
	var dir := d / length
	var bays := int(length / 6.0)
	var storeys := int(height_m / STOREY_M)
	for k in range(bays):
		var centre := a + dir * (6.0 * (k + 0.5))
		for s in range(1, storeys):
			var y := ground_y + s * STOREY_M
			var mid := Vector3(centre.x, y, centre.y) + outward * (BALCONY_DEPTH_M * 0.5)
			_box(mid, Vector3(BALCONY_WIDTH_M, BALCONY_SLAB_M, BALCONY_DEPTH_M), dir, color, uv2, out)


## A box centred at `centre` with size (along axis, up, across axis).
static func _box(centre: Vector3, size: Vector3, axis: Vector2, color: Color, uv2: Vector2, out: RoadMeshBuilder.ChunkTriangles) -> void:
	var ax := Vector3(axis.x, 0.0, axis.y) * size.x * 0.5
	var az := Vector3(-axis.y, 0.0, axis.x) * size.z * 0.5
	var lo := centre - Vector3(0.0, size.y * 0.5, 0.0)
	_prism(lo - ax - az, lo + ax - az, lo + ax + az, lo - ax + az, size.y, color, uv2, out)


## Walls and top of a prism over the base quad p0..p3 of height h, every face wound outward.
static func _prism(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, h: float, color: Color, uv2: Vector2, out: RoadMeshBuilder.ChunkTriangles) -> void:
	var up := Vector3(0.0, h, 0.0)
	var base: Array[Vector3] = [p0, p1, p2, p3]
	var centre := (p0 + p1 + p2 + p3) * 0.25 + up * 0.5
	for i in range(4):
		var a: Vector3 = base[i]
		var b: Vector3 = base[(i + 1) % 4]
		_tri_out(a, b, b + up, color, uv2, centre, out)
		_tri_out(a, b + up, a + up, color, uv2, centre, out)
	_tri_out(p0 + up, p1 + up, p2 + up, color, uv2, centre, out)
	_tri_out(p0 + up, p2 + up, p3 + up, color, uv2, centre, out)


## Triangle wound clockwise seen from outside: its cross-product normal points toward `centre`.
static func _tri_out(a: Vector3, b: Vector3, c: Vector3, color: Color, uv2: Vector2, centre: Vector3, out: RoadMeshBuilder.ChunkTriangles) -> void:
	var n := (b - a).cross(c - a)
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - centre) > 0.0:
		var t := b
		b = c
		c = t
	out.add_triangle_uv(a, b, c, color, Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y), uv2)


static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FACADE_SHADER
	return m
