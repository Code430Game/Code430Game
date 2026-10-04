class_name CarMesh
extends RefCounted
## Procedural low-poly car body shared by the player car and traffic.
##
## Approach: a side profile (z along the car, y up; -Z is the front) is extruded across the
## width into a closed hull, with the cabin a little narrower than the body. Four surfaces:
## 0 body (white vertex colour, so a material tint or a MultiMesh instance colour paints it),
## 1 dark parts (glass, trim, wheels), 2 headlights, 3 tail lights (their own surface so the
## player's car can swap in a brake-light material). The origin is the chassis underside at
## the car's centre.

const LENGTH_M := 4.3
const WIDTH_M := 1.8
const WHEEL_RADIUS_M := 0.33
const WHEEL_WIDTH_M := 0.22
const WHEEL_X_M := 0.78
const WHEEL_Z_M := 1.35
## Raise the mesh origin this much above the road so the wheel bottoms touch it.
const GROUND_LIFT_M := 0.16
const GLASS_COLOR := Color(0.14, 0.17, 0.21)
const DARK_COLOR := Color(0.09, 0.09, 0.10)
const HEADLIGHT_COLOR := Color(1.0, 0.97, 0.85)
const TAILLIGHT_COLOR := Color(0.9, 0.12, 0.1)

## Body profile as (z, y) pairs from the front bumper over the roof to the rear bumper.
## Rows tagged glass become surface 1.
const PROFILE := [
	[-2.15, 0.18, false], [-2.15, 0.52, false], [-1.95, 0.62, false], [-0.95, 0.72, false],  # bumper, hood
	[-0.95, 0.74, true], [-0.35, 1.32, true],  # windscreen
	[-0.35, 1.34, false], [0.95, 1.34, false],  # roof
	[0.95, 1.32, true], [1.45, 0.78, true],  # rear glass
	[1.45, 0.76, false], [2.15, 0.70, false], [2.15, 0.18, false],  # trunk, rear bumper
]


## Builds the mesh. With wheels, dark cylinders are included (traffic); the player car has
## its own wheel nodes and leaves them out.
static func build(with_wheels: bool) -> ArrayMesh:
	var body := SurfaceTool.new()
	var dark := SurfaceTool.new()
	var lights := SurfaceTool.new()
	var tails := SurfaceTool.new()
	for st: SurfaceTool in [body, dark, lights, tails]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := WIDTH_M * 0.5
	var hull: Array[Vector2] = []  # the profile closed along the underside
	for row: Array in PROFILE:
		hull.append(Vector2(row[0], row[1]))
	# Extrude each profile edge across the width; the cabin rows sit slightly inboard.
	for i in range(PROFILE.size() - 1):
		var a: Array = PROFILE[i]
		var b: Array = PROFILE[i + 1]
		var glass: bool = a[2] and b[2]
		var inset_a := 0.1 if float(a[1]) > 0.75 else 0.0
		var inset_b := 0.1 if float(b[1]) > 0.75 else 0.0
		var st := dark if glass else body
		var col := GLASS_COLOR if glass else Color.WHITE
		_quad(st, Vector3(-(hw - inset_a), a[1], a[0]), Vector3(hw - inset_a, a[1], a[0]), Vector3(hw - inset_b, b[1], b[0]), Vector3(-(hw - inset_b), b[1], b[0]), col)
	# Underside.
	_quad(body, Vector3(-hw, 0.18, 2.15), Vector3(hw, 0.18, 2.15), Vector3(hw, 0.18, -2.15), Vector3(-hw, 0.18, -2.15), Color.WHITE)
	# Sides: the profile polygon, split into body and cabin parts by height.
	for side: float in [-1.0, 1.0]:
		var lower: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in hull:
			lower.append(Vector2(p.x, minf(p.y, 0.76)))
		_polygon_side(body, lower, side * hw, Color.WHITE, side)
		var upper: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in hull:
			if p.y > 0.75:
				upper.append(p)
		if upper.size() >= 3:
			var cab := PackedVector2Array()
			cab.append(Vector2(upper[0].x, 0.76))
			for p: Vector2 in upper:
				cab.append(p)
			cab.append(Vector2(upper[upper.size() - 1].x, 0.76))
			_polygon_side(dark, cab, side * (hw - 0.1), GLASS_COLOR, side)
	# Lights on the bumpers.
	for side: float in [-1.0, 1.0]:
		var x0 := side * 0.35
		var x1 := side * 0.78
		_quad(lights, Vector3(x0, 0.34, -2.151), Vector3(x1, 0.34, -2.151), Vector3(x1, 0.48, -2.151), Vector3(x0, 0.48, -2.151), HEADLIGHT_COLOR)
		_quad(tails, Vector3(x1, 0.34, 2.151), Vector3(x0, 0.34, 2.151), Vector3(x0, 0.5, 2.151), Vector3(x1, 0.5, 2.151), TAILLIGHT_COLOR)
	if with_wheels:
		for x: float in [-WHEEL_X_M, WHEEL_X_M]:
			for z: float in [-WHEEL_Z_M, WHEEL_Z_M]:
				_wheel(dark, Vector3(x, WHEEL_RADIUS_M - 0.14, z))
	var mesh := ArrayMesh.new()
	for st: SurfaceTool in [body, dark, lights, tails]:
		st.generate_normals()
		st.commit(mesh)
	mesh.surface_set_material(0, body_material(Color.WHITE))
	mesh.surface_set_material(1, dark_material())
	mesh.surface_set_material(2, light_material())
	mesh.surface_set_material(3, tail_material())
	return mesh


## One shared tail-light material: red glow after dusk (DayNight raises its energy).


static func tail_material() -> StandardMaterial3D:
	return VehicleMesh.tail_material()  # one shared instance for every vehicle


## Bright red for the player's tail lights while braking, day or night.


static func brake_material() -> StandardMaterial3D:
	return VehicleMesh.brake_material()  # one shared instance for every vehicle


## Tintable body material: vertex colour (white) times the tint, or the MultiMesh instance colour.
static func body_material(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.roughness = 0.35
	m.metallic = 0.25
	return m


static func dark_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.3
	m.metallic = 0.1
	return m


## One shared lights material for every car, so DayNight can brighten them all at once.
const LIGHT_NIGHT_ENERGY := 4.0


static func light_material() -> StandardMaterial3D:
	return VehicleMesh.light_material()  # one shared instance for every vehicle


## Quad with its front face outward: the vertex order is flipped if the normal points toward
## the car's centre (the chassis centre, 0.6 m up).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a)
	var centre := Vector3(0.0, 0.6, 0.0)
	var outward := n.dot((a + b + c + d) * 0.25 - centre) > 0.0
	var order: Array[Vector3] = [a, b, c, d]
	if not outward:
		order = [a, d, c, b]
	st.set_color(color)
	# Godot front faces are clockwise seen from outside.
	for tri: Array in [[0, 2, 1], [0, 3, 2]]:
		for k: int in tri:
			st.set_color(color)
			st.add_vertex(order[k])


## A planar polygon (z, y) at x = `x`, facing outward on `side` (-1 left, +1 right).
static func _polygon_side(st: SurfaceTool, poly: PackedVector2Array, x: float, color: Color, side: float) -> void:
	var indices := Geometry2D.triangulate_polygon(poly)
	if indices.is_empty():
		return
	for t in range(0, indices.size(), 3):
		var tri: Array[int] = [indices[t], indices[t + 1], indices[t + 2]]
		var pts: Array[Vector3] = []
		for k: int in tri:
			pts.append(Vector3(x, poly[k].y, poly[k].x))
		# Front faces are clockwise seen from outside: the cross product of the emitted
		# order must point inward, the opposite of the outward side.
		var n := (pts[1] - pts[0]).cross(pts[2] - pts[0])
		if n.x * side > 0.0:
			pts.reverse()
		for p: Vector3 in pts:
			st.set_color(color)
			st.add_vertex(p)


static func _wheel(st: SurfaceTool, centre: Vector3) -> void:
	var sides := 10
	var hwid := WHEEL_WIDTH_M * 0.5
	for i in range(sides):
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := centre + Vector3(0.0, cos(a0) * WHEEL_RADIUS_M, sin(a0) * WHEEL_RADIUS_M)
		var p1 := centre + Vector3(0.0, cos(a1) * WHEEL_RADIUS_M, sin(a1) * WHEEL_RADIUS_M)
		var tread_a := p0 + Vector3(-hwid, 0, 0)
		var tread_b := p1 + Vector3(-hwid, 0, 0)
		var tread_c := p1 + Vector3(hwid, 0, 0)
		var tread_d := p0 + Vector3(hwid, 0, 0)
		_quad_about(st, tread_a, tread_b, tread_c, tread_d, DARK_COLOR, centre)
		for x: float in [-hwid, hwid]:
			var c := centre + Vector3(x, 0, 0)
			var pts: Array[Vector3] = [c, p0 + Vector3(x, 0, 0), p1 + Vector3(x, 0, 0)]
			var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
			if n.x * x > 0.0:
				pts.reverse()  # clockwise from outside, like the body
			for p: Vector3 in pts:
				st.set_color(DARK_COLOR)
				st.add_vertex(p)


static func _quad_about(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, centre: Vector3) -> void:
	var n := (b - a).cross(c - a)
	var outward := n.dot((a + b + c + d) * 0.25 - centre) > 0.0
	var order: Array[Vector3] = [a, b, c, d]
	if not outward:
		order = [a, d, c, b]
	for tri: Array in [[0, 2, 1], [0, 3, 2]]:
		for k: int in tri:
			st.set_color(color)
			st.add_vertex(order[k])
