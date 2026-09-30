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
const VARIATION := 0.08
const FACADE_SHADER := preload("res://world/buildings/facade.gdshader")
## Facade treatments (see facade.gdshader): 0 plain, 1 punched brick, 2 glass grid, 3 stone.
const TREATMENT_PLAIN := 0
const TREATMENT_PUNCHED := 1
const TREATMENT_GLASS := 2
const TREATMENT_STONE := 3
const GLASS_MIN_HEIGHT_M := 15.0
const TALL_GLASS_HEIGHT_M := 40.0
const PLAIN_MAX_HEIGHT_M := 3.5
const STONE_KINDS := ["church", "cathedral", "university", "school", "public", "government", "hospital"]
const PLAIN_KINDS := ["garage", "garages", "shed", "roof", "industrial", "warehouse"]
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
		out.append(bld)
	return out


## Facade treatment for a building type and height.
static func treatment_for(kind: String, height_m: float) -> int:
	if height_m <= PLAIN_MAX_HEIGHT_M or kind in PLAIN_KINDS:
		return TREATMENT_PLAIN
	if height_m >= TALL_GLASS_HEIGHT_M:
		return TREATMENT_GLASS
	if kind in STONE_KINDS:
		return TREATMENT_STONE
	if kind in GLASS_KINDS and height_m >= GLASS_MIN_HEIGHT_M:
		return TREATMENT_GLASS
	return TREATMENT_PUNCHED


## Per-building seed in 0..1 from its id.
static func seed_for(id: String) -> float:
	return float(hash(id) % 10007) / 10007.0


## Colour for a building, with a small deterministic variation per id.
static func color_for(b: Building) -> Color:
	var base: Color = KIND_COLORS.get(b.kind, DEFAULT_COLOR)
	var h := float(hash(b.id) % 1000) / 1000.0
	return base.lightened((h - 0.5) * VARIATION) if h >= 0.5 else base.darkened((0.5 - h) * VARIATION)


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
	var wall := color_for(b)
	var roof := wall.darkened(ROOF_DARKEN)
	var y0 := b.ground_y - WALL_EMBED_M
	var y1 := b.ground_y + b.height_m
	var uv2 := Vector2(float(treatment_for(b.kind, b.height_m)), seed_for(b.id))
	var roof_uv2 := Vector2(-1.0, uv2.y)
	for ring in b.rings:
		var along := 0.0
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


static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FACADE_SHADER
	return m
