class_name VegetationBuilder
extends RefCounted
## Trees and bushes from vegetation.v0.json (add-vegetation 2.2): per chunk, one MultiMesh per
## archetype and LOD. LOD0 (full low-poly) only in NEAR chunks, shown up to the preset's
## `vegetation_lod0_m`; LOD1 (the same shapes in a few triangles) everywhere the chunk is built, from there out.
## Both ranges are per chunk-sized MultiMesh (measured to its middle), which is coarse but
## needs no per-frame work. The preset caps trees and bushes per chunk; the importer wrote
## each chunk's plants mapped-first, so the cap drops scattered ones first. Mapped street
## trees (sources tagged and row) get a trunk in the chunk's collision.

const SHADER := preload("res://world/vegetation/canopy.gdshader")
const TRUNK_HALF_M := 0.25
const TRUNK_HEIGHT_M := 3.0
const LOD1_END_M := 1400.0
const STREET_SOURCES := ["tagged", "row"]

static var _material: ShaderMaterial


## chunk -> {"trees": Array, "bushes": Array} of rows [x, y, z, archetype, height, crown, seed, source].
static func load_by_chunk(pack_dir: String, chunk_size: float) -> Dictionary:
	var out := {}
	var path := pack_dir.path_join("vegetation.v0.json")
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for kind: String in ["trees", "bushes"]:
		for row: Array in data.get(kind, []):
			var c := Vector2i(int(floor(float(row[0]) / chunk_size)), int(floor(float(row[2]) / chunk_size)))
			if not out.has(c):
				out[c] = {"trees": [], "bushes": []}
			(out[c][kind] as Array).append(row)
	return out


## Green areas for the maps: [{"kind", "vertices": PackedVector2Array, "triangles": PackedInt32Array}].
static func load_areas(pack_dir: String) -> Array:
	var out: Array = []
	var path := pack_dir.path_join("vegetation.v0.json")
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for a: Dictionary in data.get("areas", []):
		var verts := PackedVector2Array()
		for v: Array in a["vertices"]:
			verts.append(Vector2(float(v[0]), float(v[1])))
		out.append({"kind": str(a["kind"]), "vertices": verts, "triangles": PackedInt32Array(a["triangles"])})
	return out


static func material(sway: bool) -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	_material.set_shader_parameter("sway", sway)
	return _material


## The active preset's vegetation settings, read on the main thread (chunks build on worker
## threads, which may not touch the scene tree to find Settings).
static var _preset: Dictionary = {}


static func read_preset() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var settings: Node = tree.root.get_node_or_null("Settings") if tree != null else null
	_preset = {}
	if settings != null:
		_preset = (settings.get("presets") as Dictionary).get(str(settings.get("current_preset_name")), {}).duplicate()


static func preset_value(key: String, fallback: Variant) -> Variant:
	return _preset.get(key, fallback)


## The rows this chunk draws: the first `cap` of each kind (they are in priority order).
static func capped(entry: Dictionary) -> Dictionary:
	var trees: Array = entry.get("trees", [])
	var bushes: Array = entry.get("bushes", [])
	var tcap := int(preset_value("vegetation_trees_per_chunk", 400))
	var bcap := int(preset_value("vegetation_bushes_per_chunk", 600))
	return {"trees": trees.slice(0, mini(tcap, trees.size())), "bushes": bushes.slice(0, mini(bcap, bushes.size()))}


static func _instance(row: Array) -> Transform3D:
	var arche: String = row[3]
	var h := float(row[4])
	var crown := float(row[5])
	var ratio: float = TreeMeshes.RATIO[arche]
	var turn := float(int(row[6]) % 628) / 100.0
	var b := Basis(Vector3.UP, turn).scaled(Vector3(crown / ratio, h, crown / ratio))
	return Transform3D(b, Vector3(float(row[0]), float(row[1]) - 0.05, float(row[2])))


static func _tint(row: Array) -> Color:
	var s := int(row[6])
	var k := 0.86 + float(s % 29) / 100.0
	var warm := float((s / 29) % 11) / 100.0
	return Color(k + warm, k, k - warm * 0.5)


## Adds the chunk's vegetation nodes; returns a collision mesh of street-tree trunks (or null).
static func add_to_chunk(chunk: Node3D, entry: Dictionary, near: bool) -> ArrayMesh:
	var rows: Dictionary = capped(entry)
	var by_arche := {}
	for kind: String in ["trees", "bushes"]:
		for row: Array in rows[kind]:
			var a: String = row[3]
			if not by_arche.has(a):
				by_arche[a] = []
			(by_arche[a] as Array).append(row)
	var root := Node3D.new()
	root.name = "vegetation"  # one node for the streamer to land, not one per archetype and LOD
	chunk.add_child(root)
	var lod0_m := float(preset_value("vegetation_lod0_m", 260.0))
	var mat := material(bool(preset_value("vegetation_sway", false)))
	for a: String in by_arche:
		var list: Array = by_arche[a]
		for lod in ([0, 1] if near else [1]):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = TreeMeshes.mesh(a, lod)
			mm.instance_count = list.size()
			for i in range(list.size()):
				mm.set_instance_transform(i, _instance(list[i]))
				mm.set_instance_color(i, _tint(list[i]))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "veg_%s_lod%d" % [a, lod]
			mmi.multimesh = mm
			mmi.material_override = mat
			if lod == 0:
				mmi.visibility_range_end = lod0_m
			else:
				mmi.visibility_range_begin = lod0_m if near else 0.0
				mmi.visibility_range_end = LOD1_END_M
			if TreeMeshes.is_bush(a) or lod == 1:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
	if not near:
		return null
	var trunks := RoadMeshBuilder.ChunkTriangles.new()
	for row: Array in rows["trees"]:
		if STREET_SOURCES.has(str(row[7])):
			var top := Vector3(float(row[0]), float(row[1]) + TRUNK_HEIGHT_M, float(row[2]))
			BridgeBuilder._box(trunks, top, Vector3.RIGHT, Vector3.BACK, TRUNK_HALF_M, TRUNK_HALF_M, TRUNK_HEIGHT_M, Color.WHITE)
	return null if trunks.is_empty() else trunks.to_mesh()
