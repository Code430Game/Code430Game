class_name CharacterMesh
extends RefCounted
## A low-poly person built from primitives into one vertex-coloured surface (one draw call).
## Every part belongs to one bone of a small rig (see BONES) so a Skeleton3D can walk it;
## `build` with a pose bakes the bones in instead, for static bodies (pedestrian pools).
## Stands on y = 0, faces -Z. Height scales everything vertically; build scales widths.

const BASE_HEIGHT_M := 1.8

## Bone name -> [parent name, pivot in model space at scale 1].
const BONES: Array = [
	["hips", "", Vector3(0.0, 0.88, 0.0)],
	["spine", "hips", Vector3(0.0, 0.92, 0.0)],
	["head", "spine", Vector3(0.0, 1.50, 0.0)],
	["upper_arm_l", "spine", Vector3(0.30, 1.38, 0.0)],
	["forearm_l", "upper_arm_l", Vector3(0.30, 1.02, 0.0)],
	["upper_arm_r", "spine", Vector3(-0.30, 1.38, 0.0)],
	["forearm_r", "upper_arm_r", Vector3(-0.30, 1.02, 0.0)],
	["thigh_l", "hips", Vector3(0.11, 0.88, 0.0)],
	["shin_l", "thigh_l", Vector3(0.11, 0.46, 0.0)],
	["thigh_r", "hips", Vector3(-0.11, 0.88, 0.0)],
	["shin_r", "thigh_r", Vector3(-0.11, 0.46, 0.0)],
]
const EYE_COLOR := Color(0.08, 0.07, 0.07)
const FRAME_COLOR := Color(0.12, 0.12, 0.13)
const MOUTH_COLOR := Color(0.55, 0.30, 0.28)

static var _sphere_arrays: Array = []
static var _capsule_arrays: Array = []
static var _cylinder_arrays: Array = []


static func height_m(profile: Dictionary) -> float:
	return BASE_HEIGHT_M * float(CharacterProfile.normalise(profile)["height"])


static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	return mat


static func bone_index(name: String) -> int:
	for i in range(BONES.size()):
		if BONES[i][0] == name:
			return i
	return -1


## Pivot of a bone in model space for a profile's scale.
static func bone_pivot(i: int, profile: Dictionary) -> Vector3:
	var p := CharacterProfile.normalise(profile)
	var s := Vector3(float(p["build"]), float(p["height"]), float(p["build"]))
	return (BONES[i][2] as Vector3) * s


## Walk pose at `phase` (radians, one stride per 2 pi) blended by `amount` 0..1:
## bone name -> rotation about X (radians); hips get a vertical bob under "hips_bob".
static func walk_pose(phase: float, amount: float) -> Dictionary:
	var swing := 0.55 * amount
	var leg_l := -swing * sin(phase)
	var leg_r := swing * sin(phase)
	return {
		"thigh_l": leg_l,
		"thigh_r": leg_r,
		# Rotation about +X swings a hanging bone's lower end toward -Z, the facing direction.
		# Knees and elbows bend the other way: the heel lifts behind, the hand comes forward.
		"shin_l": -0.9 * amount * maxf(0.0, sin(phase - PI * 0.5)),
		"shin_r": -0.9 * amount * maxf(0.0, sin(phase + PI * 0.5)),
		"upper_arm_l": 0.8 * swing * sin(phase),
		"upper_arm_r": -0.8 * swing * sin(phase),
		"forearm_l": 0.35 * amount,
		"forearm_r": 0.35 * amount,
		"hips_bob": 0.025 * amount * absf(sin(phase)),
	}


## Model-space transform of bone `i` under `pose` (empty: rest).
static func bone_global(i: int, profile: Dictionary, pose: Dictionary) -> Transform3D:
	var name: String = BONES[i][0]
	var parent := bone_index(BONES[i][1])
	var pivot := bone_pivot(i, profile)
	var parent_pivot := bone_pivot(parent, profile) if parent >= 0 else Vector3.ZERO
	var local := Transform3D(Basis(Vector3.RIGHT, float(pose.get(name, 0.0))), pivot - parent_pivot)
	if name == "hips":
		local.origin.y += float(pose.get("hips_bob", 0.0))
	if parent < 0:
		return local
	return bone_global(parent, profile, pose) * local


## The body mesh. With `skinned` the surface carries bone indices and weights for a
## Skeleton3D; otherwise `pose` is baked into the vertices.
static func build(profile: Dictionary, pose: Dictionary = {}, skinned: bool = false) -> ArrayMesh:
	var p := CharacterProfile.normalise(profile)
	var sy: float = p["height"]
	var sw: float = p["build"]
	var s := Vector3(sw, sy, sw)
	var skin: Color = CharacterProfile.SKIN[p["skin"]]
	var hair: Color = CharacterProfile.HAIR_COLOUR[p["hair_colour"]]
	var top: Color = CharacterProfile.CLOTH[p["top"]]
	var bottom: Color = CharacterProfile.CLOTH[p["bottom"]]
	var shoes: Color = CharacterProfile.SHOE_COLOURS[p["shoes"]]
	var jacket := int(p["jacket"]) == 1
	var sleeve: Color = CharacterProfile.CLOTH[p["jacket_colour"]] if jacket else top
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := _Builder.new(st, p, pose, skinned, s)
	# Legs and shoes
	for side: float in [-1.0, 1.0]:
		var thigh := "thigh_l" if side > 0.0 else "thigh_r"
		var shin := "shin_l" if side > 0.0 else "shin_r"
		b.capsule(Vector3(side * 0.11, 0.68, 0.0), 0.085, 0.27, bottom, thigh)
		b.capsule(Vector3(side * 0.11, 0.27, 0.0), 0.07, 0.28, bottom, shin)
		b.box(Vector3(side * 0.11, 0.045, -0.03), Vector3(0.17, 0.09, 0.27), shoes, shin)
	# Torso, neck, jacket front
	b.capsule(Vector3(0.0, 1.13, 0.0), 0.17, 0.34, sleeve if jacket else top, "spine", Vector3(1.3, 1.0, 0.75))
	if jacket:
		b.box(Vector3(0.0, 1.10, -0.125), Vector3(0.12, 0.52, 0.03), top, "spine")
	b.cylinder(Vector3(0.0, 1.47, 0.0), 0.06, 0.10, skin, "spine")
	# Arms and hands
	for side: float in [-1.0, 1.0]:
		var upper := "upper_arm_l" if side > 0.0 else "upper_arm_r"
		var fore := "forearm_l" if side > 0.0 else "forearm_r"
		b.capsule(Vector3(side * 0.30, 1.21, 0.0), 0.065, 0.25, sleeve, upper)
		b.capsule(Vector3(side * 0.30, 0.87, 0.0), 0.055, 0.23, sleeve, fore)
		b.sphere(Vector3(side * 0.30, 0.68, 0.0), 0.06, skin, fore)
	# Head and face
	b.sphere(Vector3(0.0, 1.64, 0.0), 0.135, skin, "head", Vector3(1.0, 1.12, 1.0))
	for side: float in [-1.0, 1.0]:
		b.sphere(Vector3(side * 0.05, 1.665, -0.115), 0.02, EYE_COLOR, "head")
		b.box(Vector3(side * 0.05, 1.70, -0.125), Vector3(0.05, 0.012, 0.02), hair, "head")
	b.box(Vector3(0.0, 1.635, -0.14), Vector3(0.03, 0.05, 0.03), skin, "head")
	b.box(Vector3(0.0, 1.595, -0.125), Vector3(0.05, 0.012, 0.02), MOUTH_COLOR, "head")
	match int(p["beard"]):
		1:
			b.sphere_part(Vector3(0.0, 1.64, 0.0), 0.138, skin.lerp(hair, 0.45), "head", Vector3(1.0, 1.12, 1.0), -1.0, -0.25, true)
		2:
			b.sphere_part(Vector3(0.0, 1.62, 0.0), 0.15, hair, "head", Vector3(1.0, 1.15, 1.0), -1.0, -0.2, true)
	if int(p["glasses"]) == 1:
		for side: float in [-1.0, 1.0]:
			b.box(Vector3(side * 0.05, 1.665, -0.135), Vector3(0.062, 0.05, 0.008), FRAME_COLOR, "head", true)
		b.box(Vector3(0.0, 1.668, -0.135), Vector3(0.04, 0.008, 0.008), FRAME_COLOR, "head")
	# Hair
	match int(p["hair"]):
		1:
			b.sphere_part(Vector3(0.0, 1.655, 0.0), 0.145, hair, "head", Vector3(1.0, 1.1, 1.0), 0.05, 1.0, false)
		2:
			b.sphere_part(Vector3(0.0, 1.655, 0.0), 0.145, hair, "head", Vector3(1.0, 1.1, 1.0), 0.05, 1.0, false)
			b.box(Vector3(0.0, 1.50, 0.11), Vector3(0.26, 0.42, 0.09), hair, "head")
		3:
			b.sphere_part(Vector3(0.0, 1.655, 0.0), 0.145, hair, "head", Vector3(1.0, 1.1, 1.0), 0.05, 1.0, false)
			b.sphere(Vector3(0.0, 1.78, 0.08), 0.06, hair, "head")
		4:
			b.box(Vector3(0.0, 1.80, 0.0), Vector3(0.05, 0.12, 0.26), hair, "head")
		5:
			b.sphere_part(Vector3(0.0, 1.655, 0.0), 0.145, hair, "head", Vector3(1.0, 1.1, 1.0), 0.05, 1.0, false)
			b.capsule(Vector3(0.0, 1.50, 0.14), 0.035, 0.27, hair, "head")
	match int(p["hat"]):
		1:
			b.sphere_part(Vector3(0.0, 1.66, 0.0), 0.15, top, "head", Vector3(1.0, 1.0, 1.0), 0.03, 1.0, false)
			b.box(Vector3(0.0, 1.70, -0.19), Vector3(0.26, 0.02, 0.14), top, "head")
		2:
			b.sphere_part(Vector3(0.0, 1.67, 0.0), 0.155, bottom, "head", Vector3(1.0, 1.05, 1.0), -0.15, 1.0, false)
	st.generate_normals()
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, material())
	return mesh


## Inverse bind transforms for a Skeleton3D skin, in bone order.
static func skin_for(profile: Dictionary) -> Skin:
	var skin := Skin.new()
	for i in range(BONES.size()):
		skin.add_named_bind(BONES[i][0], Transform3D(Basis(), -bone_pivot(i, profile)))
	return skin


static func _primitive(kind: String) -> Array:
	match kind:
		"sphere":
			if _sphere_arrays.is_empty():
				var m := SphereMesh.new()
				m.radius = 1.0
				m.height = 2.0
				m.radial_segments = 10
				m.rings = 5
				_sphere_arrays = m.get_mesh_arrays()
			return _sphere_arrays
		"capsule":
			if _capsule_arrays.is_empty():
				var m := CapsuleMesh.new()
				m.radius = 1.0
				m.height = 2.0  # unit: a sphere; the builder stretches the middle
				m.radial_segments = 8
				m.rings = 3
				_capsule_arrays = m.get_mesh_arrays()
			return _capsule_arrays
		_:
			if _cylinder_arrays.is_empty():
				var m := CylinderMesh.new()
				m.top_radius = 1.0
				m.bottom_radius = 1.0
				m.height = 1.0
				m.radial_segments = 8
				m.rings = 1
				_cylinder_arrays = m.get_mesh_arrays()
			return _cylinder_arrays


## Emits parts into the SurfaceTool: vertices scaled, posed or weighted, and coloured.
class _Builder:
	var st: SurfaceTool
	var profile: Dictionary
	var pose: Dictionary
	var skinned: bool
	var scale: Vector3
	var _bone_xf: Dictionary = {}  # name -> posed transform * inverse bind, model space

	func _init(tool: SurfaceTool, p: Dictionary, pose_in: Dictionary, skinned_in: bool, s: Vector3) -> void:
		st = tool
		profile = p
		pose = pose_in
		skinned = skinned_in
		scale = s
		if not skinned:
			for i in range(CharacterMesh.BONES.size()):
				var name: String = CharacterMesh.BONES[i][0]
				_bone_xf[name] = CharacterMesh.bone_global(i, p, pose) * Transform3D(Basis(), -CharacterMesh.bone_pivot(i, p))

	func _emit(v: Vector3, n: Vector3, color: Color, bone: String) -> void:
		var pos := v * scale
		if skinned:
			var idx := CharacterMesh.bone_index(bone)
			st.set_bones(PackedInt32Array([idx, 0, 0, 0]))
			st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
		else:
			var xf: Transform3D = _bone_xf[bone]
			pos = xf * pos
			n = (xf.basis * n).normalized()
		st.set_color(color)
		st.set_normal(n)
		st.add_vertex(pos)

	## Adds a primitive's triangles transformed by `xf` (applied before the body scale),
	## keeping a triangle only when `keep` is null or returns true for its local centroid.
	func _primitive_part(kind: String, xf: Transform3D, color: Color, bone: String, keep: Callable) -> void:
		var arrays := CharacterMesh._primitive(kind)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3):
			var i0 := indices[t]
			var i1 := indices[t + 1]
			var i2 := indices[t + 2]
			if keep.is_valid() and not keep.call((verts[i0] + verts[i1] + verts[i2]) / 3.0):
				continue
			for i: int in [i0, i1, i2]:
				_emit(xf * verts[i], (xf.basis * normals[i]).normalized(), color, bone)

	func sphere(centre: Vector3, radius: float, color: Color, bone: String, shape: Vector3 = Vector3.ONE) -> void:
		_primitive_part("sphere", Transform3D(Basis().scaled(shape * radius), centre), color, bone, Callable())

	## Part of a sphere: local y between `y_min` and `y_max` (unit sphere), and the front half only when `front`.
	func sphere_part(centre: Vector3, radius: float, color: Color, bone: String, shape: Vector3, y_min: float, y_max: float, front: bool) -> void:
		var keep := func(c: Vector3) -> bool: return c.y >= y_min and c.y <= y_max and (not front or c.z < 0.0)
		_primitive_part("sphere", Transform3D(Basis().scaled(shape * radius), centre), color, bone, keep)

	## A capsule of `radius` whose straight middle is `length` long (total length + 2 radius), along Y.
	## The unit primitive is a sphere; the caps are pushed apart by half the length.
	func capsule(centre: Vector3, radius: float, length: float, color: Color, bone: String, shape: Vector3 = Vector3.ONE) -> void:
		var arrays := CharacterMesh._primitive("capsule")
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var half := length * 0.5
		for t in range(0, indices.size(), 3):
			for k in range(3):
				var i := indices[t + k]
				var v := verts[i]
				var stretched := Vector3(v.x * radius * shape.x, v.y * radius * shape.y + (half if v.y > 0.0 else -half), v.z * radius * shape.z)
				var n := Vector3(normals[i].x / shape.x, normals[i].y / shape.y, normals[i].z / shape.z).normalized()
				_emit(centre + stretched, n, color, bone)

	func cylinder(centre: Vector3, radius: float, length: float, color: Color, bone: String) -> void:
		_primitive_part("cylinder", Transform3D(Basis().scaled(Vector3(radius, length, radius)), centre), color, bone, Callable())

	## An axis-aligned box; `hollow` leaves out the two faces normal to Z (a frame).
	func box(centre: Vector3, size: Vector3, color: Color, bone: String, hollow: bool = false) -> void:
		var h := size * 0.5
		var faces: Array = [
			[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.BACK, Vector3.UP],
			[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
			[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
		]
		for f: Array in faces:
			var n: Vector3 = f[0]
			if hollow and absf(n.z) > 0.5:
				continue
			var u: Vector3 = f[1]
			var v: Vector3 = f[2]
			var c := centre + n * h
			var eu := u * h
			var ev := v * h
			var a := c - eu - ev
			var b2 := c + eu - ev
			var cc := c + eu + ev
			var d := c - eu + ev
			for tri: Array in [[a, cc, b2], [a, d, cc]]:
				for q: Vector3 in tri:
					_emit(q, n, color, bone)
