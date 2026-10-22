class_name GlbChunks
extends RefCounted
## GLB export and import of chunk nodes. Mesh instance names carry the LOD role
## (roads_lod0, terrain_lod1, ...) so visibility ranges and collision can be
## restored after import; glTF itself has no LOD concept.


const BUILD_MANIFEST := "build.json"
## Bump whenever mesh generation changes, so chunks built by older code are rebuilt.
const GENERATOR_VERSION := 11  # 11: black shingle house roofs


## Pack files that never feed chunk geometry: the manifest, ads, service places, importer
## overrides and the validation report. Editing one must not throw the chunk cache away.
const NON_GEOMETRY_FILES: PackedStringArray = [
	"pack.json", "ads.v0.json", "services.v0.json", "overrides.json", "validation_report.json", "validation_report.md",
]


## Hash of every geometry input in the pack (road graph, terrain and its images, water,
## buildings, barriers, bridges, parking, vegetation, and any file added later), so stale
## chunks can be detected. Everything but the known non-geometry files counts, so a new input
## file is covered without a list going stale, while a regenerated validation report or an ad
## edit keeps the cache.
static func inputs_hash(pack_dir: String) -> String:
	var parts := PackedStringArray([str(GENERATOR_VERSION)])
	for rel in MapPack.pack_files(pack_dir):
		if rel in NON_GEOMETRY_FILES or rel.ends_with(".md"):
			continue
		parts.append("%s=%s" % [rel, FileAccess.get_md5(pack_dir.path_join(rel))])
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
static func import_chunk(path: String, road_material: Material, terrain_material: Material, with_collision: bool, water_material: Material = null, marking_material: Material = null, building_material: Material = null, sidewalk_material: Material = null, barrier_material: Material = null) -> Node3D:
	var materials := {"road": road_material, "terrain": terrain_material, "water": water_material, "marking": marking_material, "building": building_material, "sidewalk": sidewalk_material, "barrier": barrier_material}
	var parts := import_chunk_parts(path, materials, MapPack.Tier.NEAR)
	if parts.is_empty():
		return null
	if with_collision:
		MapPack.attach_collision(parts)
	return parts["node"]


## Reads a cached chunk and builds its mesh instances at `tier`, off the scene tree and the
## physics server (safe on a worker thread). Same result shape as MapPack.build_chunk_meshes;
## empty when the file cannot be read.
static func import_chunk_parts(path: String, materials: Dictionary, tier: int) -> Dictionary:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("GlbChunks: cannot read %s" % path)
		return {}
	var scene := doc.generate_scene(state)
	if scene == null:
		return {}
	var near := tier >= MapPack.Tier.NEAR
	var chunk := Node3D.new()
	chunk.name = path.get_file().get_basename()
	var collision_meshes: Array[Mesh] = []
	var water_mesh: Mesh = null
	for child in scene.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var role := mi.name
			if not near and role in MapPack.NEAR_ROLES:
				continue
			scene.remove_child(mi)
			mi.owner = null
			chunk.add_child(mi)
			var ranges := _ranges_for(role)
			if not near and ranges.x > 0.0 and ranges.x < MapPack.TERRAIN_LOD1_END_M:
				ranges.x = 0.0  # the far mesh stands in for LOD0 at this tier
			mi.visibility_range_begin = ranges.x
			mi.visibility_range_end = ranges.y
			mi.visibility_range_begin_margin = MapPack.LOD_FADE_M if ranges.x > 0.0 else 0.0
			mi.visibility_range_end_margin = MapPack.LOD_FADE_M if ranges.y < MapPack.TERRAIN_LOD2_END_M else 0.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if role == "water":
				mi.material_override = materials.get("water") if materials.get("water") != null else WaterBuilder.material()
				water_mesh = mi.mesh
			elif role == "markings_lod0" or role == "parking_markings_lod0":
				mi.material_override = materials.get("marking") if materials.get("marking") != null else MarkingBuilder.material()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif role.begins_with("buildings"):
				mi.material_override = materials.get("building") if materials.get("building") != null else BuildingBuilder.material()
			elif role == "sidewalks_lod0":
				mi.material_override = materials.get("sidewalk") if materials.get("sidewalk") != null else SidewalkBuilder.material()
			elif role == "barriers_lod0" or role.begins_with("yards"):
				mi.material_override = materials.get("barrier") if materials.get("barrier") != null else BarrierBuilder.material()
			else:
				mi.material_override = materials.get("terrain") if role.begins_with("terrain") else materials.get("road")
			if near and role in ["roads_lod0", "junctions_lod0", "terrain_lod0", "buildings_lod0", "sidewalks_lod0", "barriers_lod0", "yards_props_lod0"]:  # LOD0 terrain: see MapPack.build_chunk_meshes (#27)
				if role == "terrain_lod0":
					collision_meshes.append_array(MapPack.split_for_collision(mi.mesh, 4))
				else:
					collision_meshes.append(mi.mesh)
	scene.free()
	return {"node": chunk, "collision_meshes": collision_meshes, "water_mesh": water_mesh, "tier": tier}


static func _ranges_for(role: String) -> Vector2:
	match role:
		"parking_lod0":
			return Vector2(0.0, MapPack.TERRAIN_LOD1_END_M)
		"parking_markings_lod0":
			return Vector2(0.0, 350.0)
		"parking_props_lod0":
			return Vector2(0.0, MapPack.ROAD_LOD0_END_M)
		"yards_lod0", "yards_props_lod0":
			return Vector2(0.0, YardBuilder.VISIBLE_TO_M)
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
		"markings_lod0":
			return Vector2(0.0, 350.0)
		"sidewalks_lod0":
			return Vector2(0.0, SidewalkBuilder.VISIBLE_TO_M)
		"barriers_lod0":
			return Vector2(0.0, MapPack.ROAD_LOD0_END_M)
		"buildings_lod0":
			return Vector2(0.0, MapPack.BUILDING_LOD0_END_M)
		"buildings_lod1":
			return Vector2(MapPack.BUILDING_LOD0_END_M, MapPack.BUILDING_LOD1_END_M)
	return Vector2(0.0, MapPack.TERRAIN_LOD2_END_M)
