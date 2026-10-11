class_name KitCharacter
extends RefCounted
## People from the art kit (adopt-art-kit stage 2): the Quaternius modular men and women, moved
## onto CharacterMesh's eleven-bone rig by tools/people_kit.
##
## game/assets/people/<pack>.glb holds every part of one body (Face, Hair<n>, Beard<n>, Hat<n>
## and Hat<n>Under, Outfit<n>_Top/_Legs/_Feet), each vertex's bone in its colour's red channel
## as (bone + 0.5) / 16. people.json holds per body the bone pivots, each bone's extent (for
## ragdoll shapes), the eyes (for glasses) and the names of the choices. CharacterMesh asks
## here first, so the player, actors, the crowd's pools and ragdolls all wear the kit.
##
## Each kit material is a colour role: Skin, Hair, Eye, Stubble, Top, Accent, Bottom and Shoes
## come from the profile (Accent is the jacket colour); Kit_<name> keeps the kit's colour.

const DATA_PATH := "res://assets/people/people.json"
## Off for the tests of the primitive body (CharacterMesh without the kit).
static var enabled := true
static var _data: Dictionary = {}
static var _loaded := false
## pack id -> {part name -> Array of [role (String), kit colour, verts, normals, bones]}, one
## entry per surface, unindexed (three vertices a triangle).
static var _parts: Dictionary = {}


## Whether people are drawn from the kit.
static func active() -> bool:
	return enabled and not _packs().is_empty()


## The people.json entry for a body type (0 men, 1 women); {} when there is none.
static func pack(body: int) -> Dictionary:
	var packs := _packs()
	for id: String in packs:
		if int(packs[id].get("body", -1)) == body:
			return packs[id]
	return {}


## Bone pivot in model space at scale 1 (height and build 1.0).
static func pivot(body: int, bone: String) -> Vector3:
	var p: Array = pack(body).get("pivots", {}).get(bone, [0.0, 0.0, 0.0])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## A bone's extent on the plain body at scale 1: AABB in model space.
static func bone_box(body: int, bone: String) -> AABB:
	var b: Dictionary = pack(body).get("bones", {}).get(bone, {})
	var lo: Array = b.get("min", [0.0, 0.0, 0.0])
	var hi: Array = b.get("max", [0.0, 0.0, 0.0])
	var a := Vector3(float(lo[0]), float(lo[1]), float(lo[2]))
	return AABB(a, Vector3(float(hi[0]), float(hi[1]), float(hi[2])) - a)


## The names of a choice ("hair", "beard", "hat", "outfit") for a body type.
static func choices(body: int, key: String) -> PackedStringArray:
	return PackedStringArray(pack(body).get(key, []))


## How many entries a choice has: the most over the body types (each pack lists the same
## number, so a profile keeps its index when the body changes).
static func count(key: String) -> int:
	var n := 0
	for id: String in _packs():
		n = maxi(n, (_packs()[id].get(key, []) as Array).size())
	return n


## The index of a named choice for a body type (roles ask for "uniform", "worker", "punk"),
## or 0 when it is not there.
static func index_of(body: int, key: String, name: String) -> int:
	var i := choices(body, key).find(name)
	return maxi(i, 0)


## The parts a profile wears, by name in the body's model.
static func part_names(profile: Dictionary) -> PackedStringArray:
	var p := CharacterProfile.normalise(profile)
	var k := pack(int(p["body"]))
	var out := PackedStringArray(["Face"])
	var hat := int(p["hat"])
	var hat_parts: Array = k.get("hat_parts", [])
	if hat > 0 and hat < hat_parts.size() and str(hat_parts[hat]) != "":
		out.append(str(hat_parts[hat]))
		var under := str((k.get("hat_under", []) as Array)[hat])
		if under != "":
			out.append(under)  # the hair that shows below the hat stands in for the style
	else:
		var hair_parts: Array = k.get("hair_parts", [])
		var h := str(hair_parts[clampi(int(p["hair"]), 0, hair_parts.size() - 1)]) if not hair_parts.is_empty() else ""
		if h != "":
			out.append(h)
	var beard_parts: Array = k.get("beard_parts", [])
	if not beard_parts.is_empty():
		var b := str(beard_parts[clampi(int(p["beard"]), 0, beard_parts.size() - 1)])
		if b != "":
			out.append(b)
	var o := clampi(int(p["outfit"]), 0, maxi(choices(int(p["body"]), "outfit").size() - 1, 0))
	for slot: String in ["Top", "Legs", "Feet"]:
		out.append("Outfit%d_%s" % [o, slot])
	return out


## Calls `emit.call(vertex, normal, colour, bone)` for every vertex of the profile's parts, three
## a triangle, at scale 1 in the rest pose.
static func each_vertex(profile: Dictionary, emit: Callable) -> void:
	var p := CharacterProfile.normalise(profile)
	var parts := _model(int(p["body"]))
	for name in part_names(p):
		for surface: Array in parts.get(name, []):
			var colour := role_colour(str(surface[0]), surface[1], p)
			var verts: PackedVector3Array = surface[2]
			var normals: PackedVector3Array = surface[3]
			var bones: PackedInt32Array = surface[4]
			for i in range(verts.size()):
				emit.call(verts[i], normals[i], colour, bones[i])


## Triangles a profile is drawn with (tests and budgets).
static func triangles(profile: Dictionary) -> int:
	var n := 0
	var parts := _model(int(CharacterProfile.normalise(profile)["body"]))
	for name in part_names(profile):
		for surface: Array in parts.get(name, []):
			n += (surface[2] as PackedVector3Array).size() / 3
	return n


## The vertex colour for a role (linear, as CharacterMesh's materials read vertex colours).
static func role_colour(role: String, kit: Color, p: Dictionary) -> Color:
	var cloth := CharacterProfile.palette("cloth")
	var skin: Color = CharacterProfile.palette("skin")[p["skin"]]
	var hair: Color = CharacterProfile.palette("hair_colour")[p["hair_colour"]]
	match role:
		"Skin":
			return skin
		"Hair":
			return hair
		"Eye":
			return CharacterMesh.EYE_COLOR
		"Stubble":
			return skin.lerp(hair, 0.45)
		"Top":
			return cloth[p["top"]]
		"Accent":
			return cloth[p["jacket_colour"]]
		"Bottom":
			return cloth[p["bottom"]]
		"Shoes":
			return CharacterProfile.palette("shoes")[p["shoes"]]
	return kit


static func _packs() -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(DATA_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if parsed is Dictionary:
				_data = parsed
	return _data.get("packs", {})


## A body's parts, loaded once from its model.
static func _model(body: int) -> Dictionary:
	var k := pack(body)
	var path := str(k.get("model", ""))
	if _parts.has(path):
		return _parts[path]
	var parts := {}
	_parts[path] = parts
	var scene := load(path) as PackedScene if path != "" and ResourceLoader.exists(path) else null
	if scene == null:
		push_error("KitCharacter: cannot load %s" % path)
		return parts
	var root := scene.instantiate() as Node3D
	for mi: MeshInstance3D in KitVehicle._meshes(root):
		var xf := KitVehicle._to_root(mi, root)
		var basis := xf.basis.inverse().transposed()
		var surfaces: Array = []
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var role := mat.resource_name if mat != null else ""
			var kit := mat.albedo_color.srgb_to_linear() if mat != null else Color.MAGENTA
			if role.begins_with("Kit_"):
				role = "Kit"
			var arrays := mi.mesh.surface_get_arrays(s)
			var v_in: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n_in: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var c_in: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var order := PackedInt32Array(range(v_in.size()))
			if arrays[Mesh.ARRAY_INDEX] != null:
				order = arrays[Mesh.ARRAY_INDEX]
			var verts := PackedVector3Array()
			var normals := PackedVector3Array()
			var bones := PackedInt32Array()
			for i in order:
				verts.append(xf * v_in[i])
				normals.append((basis * n_in[i]).normalized())
				bones.append(clampi(int(c_in[i].r * 16.0), 0, CharacterMesh.BONES.size() - 1))
			surfaces.append([role, kit, verts, normals, bones])
		parts[str(mi.name)] = surfaces
	root.free()
	return parts
