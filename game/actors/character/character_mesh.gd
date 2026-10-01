class_name CharacterMesh
extends RefCounted
## A blocky person built from a CharacterProfile: one vertex-coloured surface, one draw call.
## Stands on y = 0, faces -Z. Height scales everything vertically; build scales widths.

const BASE_HEIGHT_M := 1.8


static func height_m(profile: Dictionary) -> float:
	return BASE_HEIGHT_M * float(CharacterProfile.normalise(profile)["height"])


static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	return mat


static func build(profile: Dictionary) -> ArrayMesh:
	var p := CharacterProfile.normalise(profile)
	var sy: float = p["height"]
	var sw: float = p["build"]
	var skin: Color = CharacterProfile.SKIN[p["skin"]]
	var hair: Color = CharacterProfile.HAIR_COLOUR[p["hair_colour"]]
	var top: Color = CharacterProfile.CLOTH[p["top"]]
	var bottom: Color = CharacterProfile.CLOTH[p["bottom"]]
	var shoes: Color = CharacterProfile.SHOE_COLOURS[p["shoes"]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := Vector3(sw, sy, sw)
	for side: float in [-1.0, 1.0]:
		_box(st, Vector3(side * 0.11, 0.44, 0.0) * s, Vector3(0.17, 0.72, 0.19) * s, bottom)
		_box(st, Vector3(side * 0.11, 0.04, -0.02) * s, Vector3(0.18, 0.08, 0.27) * s, shoes)
		_box(st, Vector3(side * 0.31, 1.13, 0.0) * s, Vector3(0.12, 0.56, 0.14) * s, top)
		_box(st, Vector3(side * 0.31, 0.80, 0.0) * s, Vector3(0.11, 0.10, 0.12) * s, skin)
		_box(st, Vector3(side * 0.06, 1.68, -0.135) * s, Vector3(0.05, 0.04, 0.02) * s, Color(0.1, 0.1, 0.1))
	_box(st, Vector3(0.0, 1.11, 0.0) * s, Vector3(0.46, 0.62, 0.26) * s, top)
	_box(st, Vector3(0.0, 1.46, 0.0) * s, Vector3(0.12, 0.08, 0.12) * s, skin)
	_box(st, Vector3(0.0, 1.64, 0.0) * s, Vector3(0.26, 0.28, 0.26) * s, skin)
	match int(p["hair"]):
		1:
			_box(st, Vector3(0.0, 1.795, 0.01) * s, Vector3(0.28, 0.07, 0.28) * s, hair)
			_box(st, Vector3(0.0, 1.70, 0.12) * s, Vector3(0.28, 0.18, 0.06) * s, hair)
		2:
			_box(st, Vector3(0.0, 1.795, 0.01) * s, Vector3(0.28, 0.07, 0.28) * s, hair)
			_box(st, Vector3(0.0, 1.56, 0.13) * s, Vector3(0.28, 0.46, 0.07) * s, hair)
	match int(p["hat"]):
		1:
			_box(st, Vector3(0.0, 1.82, 0.0) * s, Vector3(0.30, 0.08, 0.30) * s, top)
			_box(st, Vector3(0.0, 1.80, -0.20) * s, Vector3(0.30, 0.03, 0.14) * s, top)
		2:
			_box(st, Vector3(0.0, 1.80, 0.0) * s, Vector3(0.30, 0.14, 0.30) * s, bottom)
	st.generate_normals()
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, material())
	return mesh


## An axis-aligned box. Front faces are clockwise seen from outside, so each face's
## emitted triangles have their cross product pointing inward (as CarMesh does).
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
		# a, b, c, d counter-clockwise about n: (b - a) x (c - a) points along n.
		var a := c - eu - ev
		var b := c + eu - ev
		var cc := c + eu + ev
		var d := c - eu + ev
		for tri: Array in [[a, cc, b], [a, d, cc]]:
			for q: Vector3 in tri:
				st.set_color(color)
				st.add_vertex(q)
