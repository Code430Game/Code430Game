class_name GlbChunks
extends RefCounted
## GLB export and import of chunk nodes. Mesh instance names carry the LOD role
## (roads_lod0, terrain_lod1, ...) so visibility ranges and collision can be
## restored after import; glTF itself has no LOD concept.


const BUILD_MANIFEST := "build.json"
const INPUT_FILES := ["road_graph.v0.json", "terrain.json", "water.v0.json"]


## Hash of the pack files the chunks are generated from, so stale chunks can be detected.
static func inputs_hash(pack_dir: String) -> String:
	var parts := PackedStringArray()
	for name in INPUT_FILES:
		var path := pack_dir.path_join(name)
		parts.append(FileAccess.get_md5(path) if FileAccess.file_exists(path) else "-")
	return "|".join(parts).md5_text()


## True when <pack>/chunks/build.json matches the current pack inputs.
static func chunks_are_current(pack_dir: String) -> bool:
	var path := pack_dir.path_join("chunks").path_join(BUILD_MANIFEST)
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return typeof(parsed) == TYPE_DICTIONARY and parsed.get("inputs_hash", "") == inputs_hash(pack_dir)


## Exports every chunk of a loaded pack to <pack>/chunks/chunk_<cx>_<cz>.glb.
static func export_all(pack: MapPack) -> int:
	var out_dir := pack.pack_dir.path_join("chunks")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var road_result := RoadMeshBuilder.build(pack.graph, pack.junctions)
	var count := 0
	for entry in pack.terrain_index.get("chunks", []):
		var coord := Vector2i(int(entry["cx"]), int(entry["cz"]))
		var heights := TerrainBuilder.load_chunk(pack.pack_dir, pack.terrain_index, entry)
		if heights == null:
			continue
		var chunk := pack.build_chunk(coord, heights, road_result, false)
		if export_chunk(chunk, out_dir.path_join("chunk_%d_%d.glb" % [coord.x, coord.y])) == OK:
			count += 1
		chunk.free()
	var manifest := FileAccess.open(out_dir.path_join(BUILD_MANIFEST), FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(JSON.stringify({"inputs_hash": inputs_hash(pack.pack_dir), "chunks": count}, "  ") + "\n")
	return count


## Writes one chunk node tree to a GLB file.
static func export_chunk(chunk: Node3D, path: String) -> Error:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(chunk, state)
	if err != OK:
		push_error("GlbChunks: append_from_scene failed for %s: %s" % [chunk.name, error_string(err)])
		return err
	err = doc.write_to_filesystem(state, path)
	if err != OK:
		push_error("GlbChunks: write failed for %s: %s" % [path, error_string(err)])
	return err


## Reads a chunk GLB back into a node tree with visibility ranges and collision restored.
static func import_chunk(path: String, road_material: Material, terrain_material: Material, with_collision: bool, water_material: Material = null) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("GlbChunks: cannot read %s" % path)
		return null
	var scene := doc.generate_scene(state)
	if scene == null:
		return null
	var chunk := Node3D.new()
	chunk.name = path.get_file().get_basename()
	var collision_meshes: Array[Mesh] = []
	for child in scene.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var role := mi.name
			scene.remove_child(mi)
			mi.owner = null
			chunk.add_child(mi)
			var ranges := _ranges_for(role)
			mi.visibility_range_begin = ranges.x
			mi.visibility_range_end = ranges.y
			if role == "water":
				mi.material_override = water_material if water_material != null else WaterBuilder.material()
			else:
				mi.material_override = terrain_material if role.begins_with("terrain") else road_material
			if role in ["roads_lod0", "junctions_lod0", "terrain_lod1"]:
				collision_meshes.append(mi.mesh)
	scene.free()
	if with_collision:
		chunk.add_child(MapPack.build_collision(collision_meshes))
	return chunk


static func _ranges_for(role: String) -> Vector2:
	match role:
		"roads_lod0":
			return Vector2(0.0, MapPack.ROAD_LOD0_END_M)
		"roads_lod1":
			return Vector2(MapPack.ROAD_LOD0_END_M, MapPack.ROAD_LOD1_END_M)
		"junctions_lod0":
			return Vector2(0.0, MapPack.ROAD_LOD1_END_M)
		"terrain_lod0":
			return Vector2(0.0, MapPack.TERRAIN_LOD0_END_M)
		"terrain_lod1":
			return Vector2(MapPack.TERRAIN_LOD0_END_M, MapPack.TERRAIN_LOD1_END_M)
		"terrain_lod2":
			return Vector2(MapPack.TERRAIN_LOD1_END_M, MapPack.TERRAIN_LOD2_END_M)
		"water":
			return Vector2(0.0, MapPack.TERRAIN_LOD2_END_M)
	return Vector2(0.0, MapPack.TERRAIN_LOD2_END_M)
