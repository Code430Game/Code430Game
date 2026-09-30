class_name MapPack
extends RefCounted
## Loads a data-only map pack and turns it into chunk scene nodes.
##
## Chunk layout (one Node3D per 256 m chunk, named "chunk_<cx>_<cz>"):
##   roads_lod0, roads_lod1, junctions_lod0, terrain_lod0/1/2  (MeshInstance3D)
##   collision  (StaticBody3D with trimesh shapes from roads, junctions, terrain LOD1)
## Visibility ranges implement the LODs. GLB chunks written by PackBuilder use the
## same names, so the loader can consume either.

const ROAD_LOD0_END_M := 500.0
const ROAD_LOD1_END_M := 3000.0
const TERRAIN_LOD0_END_M := 400.0
const TERRAIN_LOD1_END_M := 1200.0
const TERRAIN_LOD2_END_M := 6000.0
const LOD_FADE_M := 40.0

var pack_dir: String = ""
var manifest: Dictionary = {}
var graph: RoadGraph
var terrain_index: Dictionary = {}
var junctions: Dictionary = {}
var road_material: Material
var terrain_material: Material


## Loads manifest, graph, and terrain index from a pack folder. Returns false on failure.
func load(dir: String) -> bool:
	pack_dir = dir
	var manifest_path := dir.path_join("pack.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MapPack: cannot read %s" % manifest_path)
		return false
	manifest = parsed
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
	return terrain_index.size() > 0


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
	}
	for entry in terrain_index.get("chunks", []):
		var coord := Vector2i(int(entry["cx"]), int(entry["cz"]))
		var glb := pack_dir.path_join("chunks").path_join("chunk_%d_%d.glb" % [coord.x, coord.y])
		var chunk: Node3D = null
		if FileAccess.file_exists(glb):
			chunk = GlbChunks.import_chunk(glb, road_material, terrain_material, with_collision)
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


## Builds one chunk node (meshes plus optional collision).
func build_chunk(coord: Vector2i, heights: TerrainBuilder.ChunkHeights, road_result: RoadMeshBuilder.Result, with_collision: bool) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "chunk_%d_%d" % [coord.x, coord.y]
	var collision_meshes: Array[Mesh] = []
	if road_result.roads.has(coord):
		var m0: ArrayMesh = road_result.roads[coord].to_mesh()
		chunk.add_child(_mesh_instance("roads_lod0", m0, road_material, 0.0, ROAD_LOD0_END_M))
		collision_meshes.append(m0)
	if road_result.roads_lod1.has(coord):
		var m1: ArrayMesh = road_result.roads_lod1[coord].to_mesh()
		chunk.add_child(_mesh_instance("roads_lod1", m1, road_material, ROAD_LOD0_END_M, ROAD_LOD1_END_M))
	if road_result.junctions.has(coord):
		var mj: ArrayMesh = road_result.junctions[coord].to_mesh()
		chunk.add_child(_mesh_instance("junctions_lod0", mj, road_material, 0.0, ROAD_LOD1_END_M))
		collision_meshes.append(mj)
	var t0 := TerrainBuilder.build_mesh(heights, 0)
	var t1 := TerrainBuilder.build_mesh(heights, 1)
	var t2 := TerrainBuilder.build_mesh(heights, 2)
	chunk.add_child(_mesh_instance("terrain_lod0", t0, terrain_material, 0.0, TERRAIN_LOD0_END_M))
	chunk.add_child(_mesh_instance("terrain_lod1", t1, terrain_material, TERRAIN_LOD0_END_M, TERRAIN_LOD1_END_M))
	chunk.add_child(_mesh_instance("terrain_lod2", t2, terrain_material, TERRAIN_LOD1_END_M, TERRAIN_LOD2_END_M))
	collision_meshes.append(t1)
	if with_collision:
		chunk.add_child(build_collision(collision_meshes))
	return chunk


## StaticBody3D with one trimesh shape per mesh.
static func build_collision(meshes: Array[Mesh]) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "collision"
	for m in meshes:
		var shape := CollisionShape3D.new()
		var trimesh: ConcavePolygonShape3D = m.create_trimesh_shape()
		trimesh.backface_collision = true  # a fast body that gets below a surface is pushed back, not lost
		shape.shape = trimesh
		body.add_child(shape)
	return body


static func _mesh_instance(name: String, mesh: Mesh, material: Material, begin: float, end: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = material
	mi.visibility_range_begin = begin
	mi.visibility_range_end = end
	mi.visibility_range_begin_margin = LOD_FADE_M if begin > 0.0 else 0.0
	mi.visibility_range_end_margin = LOD_FADE_M if end < TERRAIN_LOD2_END_M else 0.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	return mi


static func _road_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m


static func _terrain_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = TerrainBuilder.TERRAIN_COLOR
	m.roughness = 1.0
	return m


## The edge the spawn sits on: the westernmost eastbound motorway edge.
func spawn_edge() -> RoadGraph.RoadEdge:
	var best: RoadGraph.RoadEdge = null
	for eid in graph.sorted_edge_ids():
		var e: RoadGraph.RoadEdge = graph.edges[eid]
		if e.road_class != "motorway" or e.polyline.size() < 2:
			continue
		var d := e.polyline[e.polyline.size() - 1] - e.polyline[0]
		if d.x <= 0.0:
			continue
		if best == null or e.polyline[0].x < best.polyline[0].x:
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
	var basis := Basis.looking_at(forward.normalized(), Vector3.UP)
	return Transform3D(basis, p + Vector3(0.0, 1.0, 0.0))
