class_name BusMesh
extends RefCounted
## A city bus for the traffic MultiMesh: the same four surfaces as VehicleMesh (body takes the
## instance colour; dark glass band, wheels and bumpers; headlights; tail lights on their own
## surface for the brake shader). Forward is -Z; wheels stand on y = 0.

const LENGTH_M := 11.5
const WIDTH_M := 2.5
const HEIGHT_M := 3.0
const GROUND_LIFT_M := 0.0
const FLOOR_M := 0.45  # body underside


static func build(with_wheels: bool = true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var tools: Array[SurfaceTool] = []
	for i in range(4):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
	var hl := LENGTH_M * 0.5
	var hw := WIDTH_M * 0.5
	# Body shell
	_box(tools[0], Vector3(0.0, (FLOOR_M + HEIGHT_M) * 0.5, 0.0), Vector3(WIDTH_M, HEIGHT_M - FLOOR_M, LENGTH_M), Color.WHITE)
	# Glass band around the sides and front, a little proud of the shell
	_box(tools[1], Vector3(0.0, 2.05, 0.3), Vector3(WIDTH_M + 0.04, 1.0, LENGTH_M - 1.4), VehicleMesh.GLASS_COLOR)
	_box(tools[1], Vector3(0.0, 1.95, -hl - 0.02), Vector3(WIDTH_M - 0.3, 1.3, 0.04), VehicleMesh.GLASS_COLOR)
	# Door outline, bumpers, wheels
	_box(tools[1], Vector3(hw + 0.02, 1.2, -3.2), Vector3(0.04, 1.6, 1.1), VehicleMesh.DARK_COLOR)
	_box(tools[1], Vector3(0.0, 0.6, -hl - 0.03), Vector3(WIDTH_M, 0.35, 0.06), VehicleMesh.DARK_COLOR)
	_box(tools[1], Vector3(0.0, 0.6, hl + 0.03), Vector3(WIDTH_M, 0.35, 0.06), VehicleMesh.DARK_COLOR)
	if with_wheels:
		for x: float in [-hw + 0.25, hw - 0.25]:
			for z: float in [-3.9, 3.9]:
				_box(tools[1], Vector3(x, 0.5, z), Vector3(0.35, 1.0, 1.0), VehicleMesh.DARK_COLOR)
	# Lights
	for x: float in [-hw + 0.35, hw - 0.35]:
		_box(tools[2], Vector3(x, 0.95, -hl - 0.03), Vector3(0.35, 0.22, 0.06), VehicleMesh.HEADLIGHT_COLOR)
		_box(tools[3], Vector3(x, 1.0, hl + 0.03), Vector3(0.25, 0.5, 0.06), VehicleMesh.TAILLIGHT_COLOR)
	for st in tools:
		st.generate_normals()
		st.commit(mesh)
	mesh.surface_set_material(0, VehicleMesh.body_material(Color.WHITE))
	mesh.surface_set_material(1, VehicleMesh.dark_material())
	mesh.surface_set_material(2, VehicleMesh.light_material())
	mesh.surface_set_material(3, VehicleMesh.tail_material())
	return mesh


## Axis-aligned box with clockwise front faces seen from outside.
static func _box(st: SurfaceTool, centre: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var faces: Array = [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := centre + n * h
		var eu := u * h
		var ev := v * h
		var a := c - eu - ev
		var b := c + eu - ev
		var cc := c + eu + ev
		var d := c - eu + ev
		for tri: Array in [[a, cc, b], [a, d, cc]]:
			for q: Vector3 in tri:
				st.set_color(color)
				st.add_vertex(q)
