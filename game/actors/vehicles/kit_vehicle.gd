class_name KitVehicle
extends RefCounted
## Vehicle bodies from the art kit (game/assets/vehicles/*.glb, built by tools/vehicle_kit).
##
## A catalogue entry with `model` draws that model at LOD0; LOD1 stays the parametric body
## from VehicleMesh. The model is rebuilt into the same four surfaces VehicleMesh makes, so
## traffic, parked cars and the player's car treat both alike: 0 body (the `Paint` material,
## white vertices the tint or instance colour paints; `PaintAccent` a darker shade of it),
## 1 everything else (glass, trim, wheels, beacons: the kit colour in the vertices),
## 2 headlights, 3 tail lights. Wheel objects are named Wheel_FL/FR/RL/RR with their origin at
## the hub; `build(..., false)` leaves them out for the player's car, which has wheel nodes.

const ACCENT_SHADE := 0.72
static var _cache: Dictionary = {}  # "path:wheels" -> ArrayMesh


## Whether the entry names a model that can be loaded.
static func has_model(entry: Dictionary) -> bool:
	var path := str(entry.get("model", ""))
	return path != "" and ResourceLoader.exists(path)


## The entry's model as a four-surface ArrayMesh, with or without its wheels (cached).
static func build(entry: Dictionary, with_wheels: bool = true) -> ArrayMesh:
	var path := str(entry.get("model", ""))
	var key := "%s:%s" % [path, with_wheels]
	if _cache.has(key):
		return _cache[key]
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("KitVehicle: cannot load %s" % path)
		return null
	var root := scene.instantiate() as Node3D
	var tools: Array[SurfaceTool] = []
	for i in range(4):
		var t := SurfaceTool.new()
		t.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(t)
	var uv := TrimSheet.uv_centre("blank")
	for mi: MeshInstance3D in _meshes(root):
		if not with_wheels and mi.name.begins_with("Wheel"):
			continue
		var xf := _to_root(mi, root)
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(s)
			var slot := _slot(mat)
			var colour := _colour(mat, slot)
			_append(tools[slot], mi.mesh.surface_get_arrays(s), xf, colour, uv)
	root.free()
	var mesh := ArrayMesh.new()
	for t in tools:
		t.commit(mesh)
	mesh.surface_set_material(0, VehicleMesh.body_material(Color.WHITE))
	mesh.surface_set_material(1, VehicleMesh.dark_material())
	mesh.surface_set_material(2, VehicleMesh.light_material())
	mesh.surface_set_material(3, VehicleMesh.tail_material())
	_cache[key] = mesh
	return mesh


## Triangle count of a mesh (tests hold the kit models to a budget).
static func triangles(mesh: ArrayMesh) -> int:
	var n := 0
	for s in range(mesh.get_surface_count()):
		var idx := mesh.surface_get_array_index_len(s)
		n += (idx if idx > 0 else mesh.surface_get_array_len(s)) / 3
	return n


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


static func _to_root(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Which of the four surfaces a kit material belongs on.
static func _slot(mat: Material) -> int:
	var n := mat.resource_name if mat != null else ""
	if n.begins_with("Paint"):
		return 0
	if n.begins_with("Headlights"):
		return 2
	if n.begins_with("TailLights"):
		return 3
	return 1


## The vertex colour for a kit material: white (or the accent shade) on the body so the tint
## shows, the kit's colour elsewhere (in linear, as the shared materials read vertex colours).
static func _colour(mat: Material, slot: int) -> Color:
	if slot == 0:
		var accent := mat != null and mat.resource_name.begins_with("PaintAccent")
		return Color(ACCENT_SHADE, ACCENT_SHADE, ACCENT_SHADE) if accent else Color.WHITE
	if slot == 2:
		return VehicleMesh.HEADLIGHT_COLOR
	if slot == 3:
		return VehicleMesh.TAILLIGHT_COLOR
	var base := mat as BaseMaterial3D
	return base.albedo_color.srgb_to_linear() if base != null else VehicleMesh.DARK_COLOR


static func _append(t: SurfaceTool, arrays: Array, xf: Transform3D, colour: Color, uv: Vector2) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var basis := xf.basis.inverse().transposed()
	var order: PackedInt32Array = PackedInt32Array(range(verts.size()))
	if arrays[Mesh.ARRAY_INDEX] != null:
		order = arrays[Mesh.ARRAY_INDEX]
	for i in order:
		t.set_color(colour)
		t.set_uv(uv)
		t.set_normal((basis * normals[i]).normalized() if normals.size() > i else Vector3.UP)
		t.add_vertex(xf * verts[i])
