class_name MapPack
extends RefCounted
## Loads a data-only map pack and turns it into chunk scene nodes.
##
## Chunk layout (one Node3D per 256 m chunk, named "chunk_<cx>_<cz>"):
##   roads_lod0, roads_lod1, junctions_lod0, terrain_lod0/1/2  (MeshInstance3D)
##   collision  (StaticBody3D with trimesh shapes from roads, junctions, terrain LOD0)
## Visibility ranges implement the LODs. GLB chunks written by PackBuilder use the
## same names, so the loader can consume either.

const ROAD_LOD0_END_M := 500.0
const ROAD_LOD1_END_M := 3000.0
const TERRAIN_LOD0_END_M := 400.0
const TERRAIN_LOD1_END_M := 1200.0
const TERRAIN_LOD2_END_M := 6000.0
const BUILDING_LOD0_END_M := 600.0
const BUILDING_LOD1_END_M := 2500.0
const LOD_FADE_M := 40.0
## Detail tiers a chunk can be built at. FAR carries only the meshes visible from a distance
## (terrain LOD1/LOD2, roads LOD1, buildings LOD1, water); NEAR adds LOD0 detail and collision.
enum Tier { NONE = 0, FAR = 1, NEAR = 2 }
## Child names that only exist at the NEAR tier (dropped on a downgrade).
const NEAR_ROLES := ["roads_lod0", "junctions_lod0", "markings_lod0", "barriers_lod0", "bridges_lod0", "sidewalks_lod0", "underpasses_lod0", "buildings_lod0", "terrain_lod0", "collision", "water_floor", "parking_markings_lod0", "parking_props_lod0", "parking_signs"]
const SPAWN_MIN_EDGE_M := 150.0  # spawn edges shorter than this are usually bbox stubs
const WATER_LAYER_BIT := 2  # physics layer 2: wading floors; only people carry it in their mask
const WADE_DEPTH_M := 1.0  # how far below the surface a person stands in water

var pack_dir: String = ""
var manifest: Dictionary = {}
var ads: Array = []  # billboard ads from ads.v0.json, if the pack has any
var graph: RoadGraph
var terrain_index: Dictionary = {}
var junctions: Dictionary = {}
var road_material: Material
var terrain_material: Material
var water_material: Material
var water_polygons: Array[WaterBuilder.WaterPolygon] = []
var water_chunks: Dictionary = {}  # Vector2i -> RoadMeshBuilder.ChunkTriangles
var marking_material: Material
var marking_chunks: Dictionary = {}  # Vector2i -> RoadMeshBuilder.ChunkTriangles
var marking_visible_to_m: float = 350.0
var building_material: Material
var buildings: Array[BuildingBuilder.Building] = []
var building_chunks: Dictionary = {"lod0": {}, "lod1": {}}
var sidewalk_material: Material
var sidewalk_chunks: Dictionary = {}
var underpass_chunks: Dictionary = {}
var terrain_holes: Dictionary = {}  # chunk -> strips cut from the terrain under tunnels
var underpass_material: Material = UnderpassBuilder.material()
var barrier_material: Material
var barriers: Array[BarrierBuilder.Barrier] = []
var barrier_chunks: Dictionary = {}
var bridges: Array[BridgeBuilder.Bridge] = []
var bridge_chunks: Dictionary = {}
var bridge_material: Material
var parking_lots: Array[ParkingLotBuilder.Lot] = []
var parking_chunks: Dictionary = {}  # Vector2i -> Array of lots overlapping the chunk


## Loads manifest, graph, and terrain index from a pack folder. Returns false on failure.
func load(dir: String) -> bool:
	pack_dir = dir
	var manifest_path := dir.path_join("pack.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MapPack: cannot read %s" % manifest_path)
		return false
	manifest = parsed
	ads = []
	var ads_path := dir.path_join("ads.v0.json")
	if FileAccess.file_exists(ads_path):
		var ads_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ads_path))
		if ads_parsed is Dictionary:
			ads = ads_parsed.get("ads", [])
	if manifest.get("type", "") != "map":
		push_error("MapPack: %s is not a map pack" % manifest.get("id", dir))
		return false
	graph = RoadGraph.load_from_file(dir.path_join("road_graph.v0.json"))
	if graph == null:
		return false
	terrain_index = TerrainBuilder.load_index(dir)
	junctions = JunctionBuilder.build_all(graph)
	road_material = _road_material()
	terrain_material = _terrain_material()
	water_material = WaterBuilder.material()
	water_polygons = WaterBuilder.load_polygons(dir)
	water_chunks = WaterBuilder.build(water_polygons)
	var markings := MarkingBuilder.new()
	if markings.load_rules():
		marking_chunks = markings.build(graph, junctions)
		marking_visible_to_m = float(markings.rules["visible_to_m"])
	marking_material = MarkingBuilder.material()
	building_material = BuildingBuilder.material()
	buildings = BuildingBuilder.load_buildings(dir)
	building_chunks = BuildingBuilder.build(buildings)
	sidewalk_material = SidewalkBuilder.material()
	sidewalk_chunks = SidewalkBuilder.build(graph.pedestrian)
	underpass_chunks = UnderpassBuilder.build(graph.pedestrian)
	terrain_holes = UnderpassBuilder.holes_by_chunk(graph.pedestrian)
	barrier_material = BarrierBuilder.material()
	barriers = BarrierBuilder.load_barriers(dir)
	barrier_chunks = BarrierBuilder.build(barriers)
	bridge_material = BridgeBuilder.material()
	bridges = BridgeBuilder.load_bridges(dir)
	bridge_chunks = BridgeBuilder.build(bridges)
	parking_lots = ParkingLotBuilder.load_lots(dir, graph)
	parking_chunks = ParkingLotBuilder.by_chunk(parking_lots, RoadGeometry.CHUNK_SIZE_M)
	return terrain_index.size() > 0


## SHA-256 over pack.json plus every file's relative path and size, for co-op pack checks.
static func content_hash(dir: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(dir.path_join("pack.json")))
	var entries: Array[String] = []
	_collect_files(dir, "", entries)
	entries.sort()
	for rel in entries:
		if rel.begins_with("chunks/"):
			continue  # the GLB cache is generated locally and differs per machine
		var size := FileAccess.get_file_as_bytes(dir.path_join(rel)).size()
		ctx.update(("%s:%d\n" % [rel, size]).to_utf8_buffer())
	return ctx.finish().hex_encode()


static func _collect_files(root: String, rel_dir: String, out: Array[String]) -> void:
	var da := DirAccess.open(root.path_join(rel_dir) if rel_dir != "" else root)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name.begins_with("."):
			name = da.get_next()
			continue
		var rel := rel_dir.path_join(name) if rel_dir != "" else name
		if da.current_is_dir():
			_collect_files(root, rel, out)
		else:
			out.append(rel)
		name = da.get_next()
	da.list_dir_end()


## Manifest summary for co-op pack checks: id, version and content hash.
func manifest_summary() -> Dictionary:
	return {"id": str(manifest.get("id", "")), "version": str(manifest.get("version", "")), "hash": content_hash(pack_dir)}


## Chunk coordinates present in the terrain index.
func chunk_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for entry in terrain_index.get("chunks", []):
		out.append(Vector2i(int(entry["cx"]), int(entry["cz"])))
	return out


## Builds every chunk as children of `parent`. Returns build statistics.
func build_all_chunks(parent: Node3D, with_collision: bool = true) -> Dictionary:
	var road_result := RoadMeshBuilder.build(graph, junctions)
	var stats := {
		"chunks": 0,
		"edges_built": road_result.edges_built,
		"edges_skipped_inside_junctions": road_result.edges_skipped_inside_junctions,
		"junctions_built": road_result.junctions_built,
		"junctions_fallback": road_result.junctions_fallback,
		"road_triangles": 0,
		"terrain_triangles_lod0": 0,
		"water_polygons": water_polygons.size(),
		"buildings": buildings.size(),
	}
	var use_glb := GlbChunks.chunks_are_current(pack_dir)
	if not use_glb and DirAccess.dir_exists_absolute(pack_dir.path_join("chunks")):
		push_warning("MapPack: %s/chunks is stale or unverified; generating meshes at load" % pack_dir)
	for entry in terrain_index.get("chunks", []):
		var coord := Vector2i(int(entry["cx"]), int(entry["cz"]))
		var glb := pack_dir.path_join("chunks").path_join("chunk_%d_%d.glb" % [coord.x, coord.y])
		var chunk: Node3D = null
		if use_glb and FileAccess.file_exists(glb):
			chunk = GlbChunks.import_chunk(glb, road_material, terrain_material, with_collision, water_material, marking_material, building_material, sidewalk_material, barrier_material)
			stats["chunks_from_glb"] = stats.get("chunks_from_glb", 0) + 1
		if chunk == null:
			var heights := TerrainBuilder.load_chunk(pack_dir, terrain_index, entry)
			if heights == null:
				continue
			chunk = build_chunk(coord, heights, road_result, with_collision)
			stats["terrain_triangles_lod0"] += (heights.samples - 1) * (heights.samples - 1) * 2
		parent.add_child(chunk)
		stats["chunks"] += 1
		if road_result.roads.has(coord):
			stats["road_triangles"] += road_result.roads[coord].vertices.size() / 3
	return stats


## Builds one chunk node (meshes plus optional collision) at the NEAR tier.
func build_chunk(coord: Vector2i, heights: TerrainBuilder.ChunkHeights, road_result: RoadMeshBuilder.Result, with_collision: bool) -> Node3D:
	var parts := build_chunk_meshes(coord, heights, road_result, Tier.NEAR)
	if with_collision:
		attach_collision(parts)
	return parts["node"]


## Builds a chunk's mesh instances at `tier` without touching the scene tree or the physics
## server, so it may run on a worker thread. Returns {"node", "collision_meshes",
## "water_mesh", "tier"}; attach_collision adds the bodies on the main thread.
func build_chunk_meshes(coord: Vector2i, heights: TerrainBuilder.ChunkHeights, road_result: RoadMeshBuilder.Result, tier: int) -> Dictionary:
	var near := tier >= Tier.NEAR
	var chunk := Node3D.new()
	chunk.name = "chunk_%d_%d" % [coord.x, coord.y]
	var collision_meshes: Array[Mesh] = []
	var water_mesh: Mesh = null
	if near and road_result.roads.has(coord):
		var m0: ArrayMesh = road_result.roads[coord].to_mesh()
		chunk.add_child(_mesh_instance("roads_lod0", m0, road_material, 0.0, ROAD_LOD0_END_M))
		collision_meshes.append(m0)
	if road_result.roads_lod1.has(coord):
		var m1: ArrayMesh = road_result.roads_lod1[coord].to_mesh()
		chunk.add_child(_mesh_instance("roads_lod1", m1, road_material, ROAD_LOD0_END_M if near else 0.0, ROAD_LOD1_END_M))
	if near and road_result.junctions.has(coord):
		var mj: ArrayMesh = road_result.junctions[coord].to_mesh()
		chunk.add_child(_mesh_instance("junctions_lod0", mj, road_material, 0.0, ROAD_LOD1_END_M))
		collision_meshes.append(mj)
	if near and marking_chunks.has(coord):
		var mm: ArrayMesh = marking_chunks[coord].to_mesh()
		var markings_mi := _mesh_instance("markings_lod0", mm, marking_material, 0.0, marking_visible_to_m)
		markings_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(markings_mi)
	if near and barrier_chunks.has(coord):
		var mbar: ArrayMesh = barrier_chunks[coord].to_mesh()
		chunk.add_child(_mesh_instance("barriers_lod0", mbar, barrier_material, 0.0, ROAD_LOD0_END_M))
		collision_meshes.append(mbar)
	if near and bridge_chunks.has(coord):
		var mbr: ArrayMesh = bridge_chunks[coord].to_mesh()
		chunk.add_child(_mesh_instance("bridges_lod0", mbr, bridge_material, 0.0, ROAD_LOD1_END_M))
		collision_meshes.append(mbr)
	if near and sidewalk_chunks.has(coord):
		var ms: ArrayMesh = sidewalk_chunks[coord].to_mesh()
		chunk.add_child(_mesh_instance("sidewalks_lod0", ms, sidewalk_material, 0.0, SidewalkBuilder.VISIBLE_TO_M))
		collision_meshes.append(ms)
	if near and underpass_chunks.has(coord):
		var mu: ArrayMesh = underpass_chunks[coord].to_mesh()
		chunk.add_child(_mesh_instance("underpasses_lod0", mu, underpass_material, 0.0, SidewalkBuilder.VISIBLE_TO_M))
		collision_meshes.append(mu)
	if near and building_chunks["lod0"].has(coord):
		var mb0: ArrayMesh = building_chunks["lod0"][coord].to_mesh()
		chunk.add_child(_mesh_instance("buildings_lod0", mb0, building_material, 0.0, BUILDING_LOD0_END_M))
		collision_meshes.append(mb0)
	if building_chunks["lod1"].has(coord):
		var mb1: ArrayMesh = building_chunks["lod1"][coord].to_mesh()
		chunk.add_child(_mesh_instance("buildings_lod1", mb1, building_material, BUILDING_LOD0_END_M if near else 0.0, BUILDING_LOD1_END_M))
	if water_chunks.has(coord):
		var mw: ArrayMesh = water_chunks[coord].to_mesh()
		chunk.add_child(_mesh_instance("water", mw, water_material, 0.0, TERRAIN_LOD2_END_M))
		water_mesh = mw
	var labels: Array = []
	if parking_chunks.has(coord):
		var lots := ParkingLotBuilder.build_chunk(parking_chunks[coord], coord, heights, RoadGeometry.CHUNK_SIZE_M)
		if not (lots["surface"] as RoadMeshBuilder.ChunkTriangles).is_empty():
			var mp: ArrayMesh = (lots["surface"] as RoadMeshBuilder.ChunkTriangles).to_mesh()
			var lot_mi := _mesh_instance("parking_lod0", mp, road_material, 0.0, TERRAIN_LOD1_END_M)
			lot_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.add_child(lot_mi)
		if near and not (lots["markings"] as RoadMeshBuilder.ChunkTriangles).is_empty():
			var mk := _mesh_instance("parking_markings_lod0", (lots["markings"] as RoadMeshBuilder.ChunkTriangles).to_mesh(), marking_material, 0.0, marking_visible_to_m)
			mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.add_child(mk)
		if near and not (lots["props"] as RoadMeshBuilder.ChunkTriangles).is_empty():
			chunk.add_child(_mesh_instance("parking_props_lod0", (lots["props"] as RoadMeshBuilder.ChunkTriangles).to_mesh(), road_material, 0.0, ROAD_LOD0_END_M))
		if near:
			labels = lots["labels"]
	var holes: Array = terrain_holes.get(coord, [])
	var t1 := TerrainBuilder.build_mesh(heights, 1, holes)
	var t2 := TerrainBuilder.build_mesh(heights, 2, holes)
	if near:
		var t0 := TerrainBuilder.build_mesh(heights, 0, holes)
		chunk.add_child(_mesh_instance("terrain_lod0", t0, terrain_material, 0.0, TERRAIN_LOD0_END_M))
		# Collide with the terrain that is drawn up close. LOD1 skips every other sample, so it
		# cannot follow the ground pressed down beside a road: under the 417 at Metcalfe it rose
		# up to 1.6 m through the asphalt, an invisible wall that lifted cars onto it (#27).
		collision_meshes.append_array(split_for_collision(t0, 4))  # four LOD1-sized shapes: one per streamed frame
	chunk.add_child(_mesh_instance("terrain_lod1", t1, terrain_material, TERRAIN_LOD0_END_M if near else 0.0, TERRAIN_LOD1_END_M))
	chunk.add_child(_mesh_instance("terrain_lod2", t2, terrain_material, TERRAIN_LOD1_END_M, TERRAIN_LOD2_END_M))
	return {"node": chunk, "collision_meshes": collision_meshes, "water_mesh": water_mesh, "tier": tier, "labels": labels}


## Main thread only: adds the collision body and wading floor described by build_chunk_meshes.
## Uses the triangle lists prepared by prepare_shapes when present.
static func attach_collision(parts: Dictionary) -> void:
	var node: Node3D = parts["node"]
	if parts.has("shape_faces"):
		var body := StaticBody3D.new()
		body.name = "collision"
		for faces: PackedVector3Array in parts["shape_faces"]:
			var shape := shape_from_faces(faces)
			if shape != null:
				body.add_child(shape)
		node.add_child(body)
	else:
		node.add_child(build_collision(parts["collision_meshes"]))
	if parts.get("water_mesh") != null:
		node.add_child(build_water_floor(parts["water_mesh"]))
	# Text (lot signs) is made here, on the main thread: Label3D touches fonts and themes.
	var labels: Array = parts.get("labels", [])
	if not labels.is_empty():
		var signs := Node3D.new()
		signs.name = "parking_signs"
		for l: Array in labels:
			var label := Label3D.new()
			label.text = str(l[2])
			label.font_size = 64 if str(l[2]).length() <= 2 else 28
			label.pixel_size = 0.006
			label.modulate = Color.WHITE
			label.outline_size = 0
			label.width = 140.0
			label.autowrap_mode = TextServer.AUTOWRAP_WORD
			label.transform = Transform3D(l[1], l[0])
			label.visibility_range_end = 120.0
			signs.add_child(label)
		node.add_child(signs)


## Worker-thread step: extracts each collision mesh's triangles into parts["shape_faces"]. The
## shapes themselves are made on the main thread (shape_from_faces): creating a shape
## allocates an id in the physics server, which is not thread-safe, and doing it from worker
## threads raced the main thread's shape work ("Attempting to initialize the wrong RID",
## and the flaky test aborts that came with it).
static func prepare_shapes(parts: Dictionary) -> void:
	var faces: Array[PackedVector3Array] = []
	for m in parts["collision_meshes"]:
		if m != null and m.get_surface_count() > 0:
			var f: PackedVector3Array = m.get_faces()
			if not f.is_empty():
				faces.append(f)
	parts["shape_faces"] = faces


## Main thread only: a trimesh collision shape from a triangle list, or null when empty.
static func shape_from_faces(faces: PackedVector3Array) -> CollisionShape3D:
	if faces.is_empty():
		return null
	var trimesh := ConcavePolygonShape3D.new()
	trimesh.set_faces(faces)
	trimesh.backface_collision = true  # a fast body that gets below a surface is pushed back, not lost
	var shape := CollisionShape3D.new()
	shape.shape = trimesh
	return shape


## Drops the NEAR-only children (LOD0 meshes, collision, wading floor) from a built chunk.
static func downgrade_chunk(node: Node3D) -> void:
	for child in node.get_children():
		if child.name in NEAR_ROLES:
			node.remove_child(child)
			child.queue_free()
		elif child is MeshInstance3D and (child as MeshInstance3D).visibility_range_begin > 0.0 and (child as MeshInstance3D).visibility_range_begin < TERRAIN_LOD1_END_M:
			(child as MeshInstance3D).visibility_range_begin = 0.0  # the far mesh now stands in for LOD0
			(child as MeshInstance3D).visibility_range_begin_margin = 0.0


## Materials keyed by role family, for chunk importers running off the main thread.
func materials() -> Dictionary:
	return {"road": road_material, "terrain": terrain_material, "water": water_material, "marking": marking_material, "building": building_material, "sidewalk": sidewalk_material, "barrier": barrier_material}


## Wading floor: the water surface sunk by WADE_DEPTH_M, on the water physics layer so only
## people collide with it (cars and traffic keep their mask on the world layer).
static func build_water_floor(water_mesh: Mesh) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "water_floor"
	body.collision_layer = WATER_LAYER_BIT
	body.collision_mask = 0
	body.add_to_group("water")
	var shape := CollisionShape3D.new()
	var trimesh: ConcavePolygonShape3D = water_mesh.create_trimesh_shape()
	trimesh.backface_collision = true
	shape.shape = trimesh
	shape.position.y = -WADE_DEPTH_M
	body.add_child(shape)
	return body


## StaticBody3D with one trimesh shape per mesh.
static func build_collision(meshes: Array[Mesh]) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "collision"
	for m in meshes:
		var shape := trimesh_shape(m)
		if shape != null:
			body.add_child(shape)
	return body


## `m`'s triangles cut into `parts` plain meshes (positions only) for collision, so a big mesh
## becomes several shapes that the streamer can add on separate frames.
static func split_for_collision(m: Mesh, parts: int) -> Array[Mesh]:
	var out: Array[Mesh] = []
	var faces := m.get_faces()
	var tris := faces.size() / 3
	if tris == 0:
		return out
	var per := int(ceil(float(tris) / parts))
	for start in range(0, tris, per):
		var piece := faces.slice(start * 3, mini(start + per, tris) * 3)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = piece
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.append(mesh)
	return out


## One trimesh collision shape for a mesh (the expensive part of a chunk add), or null for
## a mesh with no triangles.
static func trimesh_shape(m: Mesh) -> CollisionShape3D:
	if m == null or m.get_surface_count() == 0:
		return null
	var trimesh: ConcavePolygonShape3D = m.create_trimesh_shape()
	if trimesh == null:
		return null
	var shape := CollisionShape3D.new()
	trimesh.backface_collision = true  # a fast body that gets below a surface is pushed back, not lost
	shape.shape = trimesh
	return shape


static func _mesh_instance(name: String, mesh: Mesh, material: Material, begin: float, end: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = material
	mi.visibility_range_begin = begin
	mi.visibility_range_end = end
	mi.visibility_range_begin_margin = LOD_FADE_M if begin > 0.0 else 0.0
	mi.visibility_range_end_margin = LOD_FADE_M if end < TERRAIN_LOD2_END_M else 0.0
	# Dithered cross-fade between LODs. A hard cut measured from each chunk's bounds could hide the
	# near mesh before the far one appeared, which showed as roads blinking out for a moment.
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mi


static func _road_material() -> Material:
	return SurfaceDetail.material("asphalt", 0.9)  # vertex colours (sRGB) with asphalt grain


static func _terrain_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = TerrainBuilder.TERRAIN_COLOR
	m.roughness = 1.0
	return m


## The edge the spawn sits on: the westernmost eastbound motorway edge.
## The eastbound motorway edge of at least SPAWN_MIN_EDGE_M whose start is nearest the map
## origin, so the game starts mid-district rather than on a stub cut by the import bbox.
func spawn_edge() -> RoadGraph.RoadEdge:
	var best: RoadGraph.RoadEdge = null
	var best_d := INF
	for eid in graph.sorted_edge_ids():
		var e: RoadGraph.RoadEdge = graph.edges[eid]
		if e.road_class != "motorway" or e.polyline.size() < 2 or e.length_m < SPAWN_MIN_EDGE_M:
			continue
		var d := e.polyline[e.polyline.size() - 1] - e.polyline[0]
		if d.x <= 0.0:
			continue
		var start := e.polyline[0]
		var dist := Vector2(start.x, start.z).length()
		if dist < best_d:
			best_d = dist
			best = e
	return best


## A sensible spawn on the highway, 20 m into the spawn edge, facing along it.
func spawn_transform() -> Transform3D:
	var best := spawn_edge()
	if best == null:
		return Transform3D(Basis(), Vector3(0, 2, 0))
	var p := RoadGeometry.point_at(best.polyline, 20.0)
	var q := RoadGeometry.point_at(best.polyline, 30.0)
	var forward := (q - p)
	forward.y = 0.0
	forward = forward.normalized()
	var lane_w := best.width_m / maxf(best.lanes_forward + best.lanes_backward, 1)
	var divider := best.width_m * 0.5 - best.lanes_forward * lane_w
	var right := Vector3(-forward.z, 0.0, forward.x)
	var basis := Basis.looking_at(forward, Vector3.UP)
	return Transform3D(basis, p + right * (divider + 0.5 * lane_w) + Vector3(0.0, 1.0, 0.0))
