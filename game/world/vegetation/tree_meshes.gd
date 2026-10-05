class_name TreeMeshes
extends RefCounted
## Tree and bush archetypes built from primitives (add-vegetation 2.1): unit height, the crown
## radius a fraction of it (RATIO), so an instance scales y by its height and x and z by
## crown / RATIO. Vertex colours only; the instance colour tints them. LOD0 stays under 150
## triangles a tree and 40 a bush; LOD1 is the same shape in a few triangles.

const ARCHETYPES: PackedStringArray = ["broadleaf", "columnar", "conifer", "bush_round", "bush_low"]
const RATIO := {"broadleaf": 0.35, "columnar": 0.2, "conifer": 0.22, "bush_round": 0.6, "bush_low": 0.9}
const TRUNK := Color(0.32, 0.23, 0.16)
const LEAF := {
	"broadleaf": Color(0.30, 0.46, 0.20),
	"columnar": Color(0.27, 0.42, 0.19),
	"conifer": Color(0.16, 0.30, 0.17),
	"bush_round": Color(0.28, 0.42, 0.20),
	"bush_low": Color(0.33, 0.45, 0.22),
}

static var _cache: Dictionary = {}


static func mesh(archetype: String, lod: int) -> ArrayMesh:
	var key := "%s:%d" % [archetype, lod]
	if not _cache.has(key):
		_cache[key] = _build(archetype) if lod == 0 else _impostor(archetype)
	return _cache[key]


static func is_bush(archetype: String) -> bool:
	return archetype.begins_with("bush")


static func _build(a: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r: float = RATIO[a]
	var leaf: Color = LEAF[a]
	match a:
		"broadleaf":
			_cylinder(st, 0.0, 0.5, 0.04, TRUNK, 8)
			_ellipsoid(st, Vector3(0, 0.62, 0), Vector3(r, r * 0.8, r), leaf, 6, 4)
			_ellipsoid(st, Vector3(r * 0.35, 0.82, -r * 0.2), Vector3(r * 0.7, r * 0.6, r * 0.7), leaf.lightened(0.06), 6, 4)
		"columnar":
			_cylinder(st, 0.0, 0.3, 0.03, TRUNK, 8)
			_ellipsoid(st, Vector3(0, 0.62, 0), Vector3(r, 0.38, r), leaf, 6, 5)
		"conifer":
			_cylinder(st, 0.0, 0.25, 0.03, TRUNK, 6)
			for k in range(3):
				var base := 0.18 + k * 0.25
				_cone(st, base, base + 0.42, r * (1.0 - k * 0.25), leaf.lightened(k * 0.04), 8)
		"bush_round":
			_ellipsoid(st, Vector3(0, 0.5, 0), Vector3(r, 0.5, r), leaf, 6, 3)
		"bush_low":
			_ellipsoid(st, Vector3(0, 0.45, 0), Vector3(r, 0.45, r * 0.7), leaf, 6, 3)
	st.generate_normals()
	return st.commit()


## LOD1: the same shape at a few triangles: a four-sided canopy (a pyramid for conifers) on a
## three-sided trunk. Crossed quads read as flat cards in the middle distance.
static func _impostor(a: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r: float = RATIO[a]
	var leaf: Color = LEAF[a]
	match a:
		"conifer":
			_cylinder(st, 0.0, 0.25, 0.03, TRUNK, 3)
			_cone(st, 0.18, 1.0, r, leaf, 4)
		"columnar":
			_cylinder(st, 0.0, 0.3, 0.03, TRUNK, 3)
			_ellipsoid(st, Vector3(0, 0.62, 0), Vector3(r, 0.38, r), leaf, 4, 2)
		"broadleaf":
			_cylinder(st, 0.0, 0.5, 0.04, TRUNK, 3)
			_ellipsoid(st, Vector3(0, 0.66, 0), Vector3(r * 1.1, r * 0.9, r * 1.1), leaf, 4, 2)
		_:
			_ellipsoid(st, Vector3(0, 0.5, 0), Vector3(r, 0.5, r), leaf, 4, 2)
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	# Godot's front face winds clockwise seen from outside: (c - a) x (b - a) points out.
	for v: Vector3 in [a, b, c]:
		st.set_color(col)
		st.add_vertex(v)


static func _cylinder(st: SurfaceTool, y0: float, y1: float, radius: float, col: Color, sides: int) -> void:
	for k in range(sides):
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := Vector3(cos(a0) * radius, y0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, y0, sin(a1) * radius)
		var q0 := Vector3(p0.x, y1, p0.z)
		var q1 := Vector3(p1.x, y1, p1.z)
		_tri(st, p0, q0, q1, col)
		_tri(st, p0, q1, p1, col)


static func _cone(st: SurfaceTool, y0: float, y1: float, radius: float, col: Color, sides: int) -> void:
	var tip := Vector3(0, y1, 0)
	for k in range(sides):
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := Vector3(cos(a0) * radius, y0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, y0, sin(a1) * radius)
		_tri(st, p0, tip, p1, col)
		_tri(st, p0, p1, Vector3(0, y0, 0), col.darkened(0.2))  # underside


static func _ellipsoid(st: SurfaceTool, c: Vector3, rad: Vector3, col: Color, seg: int, rings: int) -> void:
	for i in range(rings):
		var t0 := PI * i / rings
		var t1 := PI * (i + 1) / rings
		for k in range(seg):
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var p00 := c + Vector3(sin(t0) * cos(a0) * rad.x, cos(t0) * rad.y, sin(t0) * sin(a0) * rad.z)
			var p01 := c + Vector3(sin(t0) * cos(a1) * rad.x, cos(t0) * rad.y, sin(t0) * sin(a1) * rad.z)
			var p10 := c + Vector3(sin(t1) * cos(a0) * rad.x, cos(t1) * rad.y, sin(t1) * sin(a0) * rad.z)
			var p11 := c + Vector3(sin(t1) * cos(a1) * rad.x, cos(t1) * rad.y, sin(t1) * sin(a1) * rad.z)
			var shade := col.darkened(0.12 * float(i) / rings)
			if i > 0:
				_tri(st, p00, p01, p11, shade)
			if i < rings - 1:
				_tri(st, p00, p11, p10, shade)


static func triangles(m: Mesh) -> int:
	return m.surface_get_array_len(0) / 3
