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
const NEAR_ROLES := ["roads_lod0", "junctions_lod0", "markings_lod0", "barriers_lod0", "bridges_lod0", "garages_lod0", "garage_lights", "sidewalks_lod0", "underpasses_lod0", "buildings_lod0", "terrain_lod0", "collision", "water_floor", "parking_markings_lod0", "parking_props_lod0", "parking_signs", "yards_lod0", "yards_props_lod0"]
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
var garages: Array[GarageBuilder.Garage] = []
var garage_chunks: Dictionary = {}  # chunk -> ChunkTriangles (ramps, doors, garage boxes)
var garage_light_chunks: Dictionary = {}
var garage_material: Material
var garage_light_material: Material
var vegetation_chunks: Dictionary = {}  # chunk -> {"trees", "bushes"} rows, priority order
var green_areas: Array = []  # for the maps
var services: Array[Services.Place] = []  # police stations, hospitals, fire stations, helipads
var turfs: Array[Turf] = []  # ground a faction holds (add-hostile-gang)
var parking_lots: Array[ParkingLotBuilder.Lot] = []
var parking_chunks: Dictionary = {}  # Vector2i -> Array of lots overlapping the chunk
var yard_chunks: Dictionary = {}  # Vector2i -> {"yards", "fences"} (YardBuilder.by_chunk)


## The pack ids of the districts played together (add-district-stitching); empty for one.
var districts: PackedStringArray = []
## Why the districts asked for couldn't be played together ("" when they could).
var set_refusal: String = ""
## How many border crossings joined between the districts.
var joined_crossings: int = 0
## How far a load or load_districts has got, 0 to 1, and what it is on: a loading screen reads
## these from the main thread while the load runs on another.
var progress: float = 0.0
var progress_text: String = ""
var _sink: MapPack = null  # a district part reports into the set loading it
var _span := Vector2(0.0, 1.0)  # the part of the set's bar this load fills
var _content_hash: String = ""  # cached per load: the pack files cannot change underneath a loaded pack
var content_hash_runs: int = 0  # how many times the files were hashed, for tests


## Loads manifest, graph, and terrain index from a pack folder. Returns false on failure.
func load(dir: String) -> bool:
	if _sink == null:
		step_times = []
		_step_at_us = 0
	districts = []
	pack_dir = dir
	_content_hash = ""
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
	_step(0.0, "roads")
	# A district of a set reads the data only: the set builds the meshes once, for the whole map.
	var part := _sink != null
	if part:
		_graph_dict = _read_json(dir.path_join("road_graph.v0.json"))
		graph = RoadGraph.from_dict(_graph_dict) if not _graph_dict.is_empty() else null
	else:
		graph = RoadGraph.load_from_file(dir.path_join("road_graph.v0.json"))
	if graph == null:
		return false
	terrain_index = TerrainBuilder.load_index(dir)
	_step(0.15, "junctions")
	junctions = JunctionBuilder.build_all(graph)
	_step(0.3, "water and markings")
	road_material = _road_material()
	terrain_material = _terrain_material()
	water_material = WaterBuilder.material()
	water_polygons = WaterBuilder.load_polygons(dir)
	water_chunks = WaterBuilder.build(water_polygons)
	_step(0.35, "markings")
	var markings := MarkingBuilder.new()
	if markings.load_rules():
		marking_chunks = markings.build(graph, junctions) if not part else {}
		marking_visible_to_m = float(markings.rules["visible_to_m"])
	marking_material = MarkingBuilder.material()
	_step(0.45, "buildings")
	building_material = BuildingBuilder.material()
	buildings = BuildingBuilder.load_buildings(dir)
	_step(0.55, "building meshes")
	if not part:
		building_chunks = BuildingBuilder.build(buildings)
	_step(0.65, "sidewalks")
	sidewalk_material = SidewalkBuilder.material()
	if not part:
		sidewalk_chunks = SidewalkBuilder.build(graph.pedestrian)
		underpass_chunks = UnderpassBuilder.build(graph.pedestrian)
		terrain_holes = UnderpassBuilder.holes_by_chunk(graph.pedestrian)
	_step(0.75, "curbs, bridges and lots")
	barrier_material = BarrierBuilder.material()
	barriers = BarrierBuilder.clip_curbs(BarrierBuilder.load_barriers(dir), junctions)
	_step(0.78, "curb meshes")
	if not part:
		barrier_chunks = BarrierBuilder.build(barriers)
	_step(0.8, "bridges")
	bridge_material = BridgeBuilder.material()
	bridges = BridgeBuilder.load_bridges(dir)
	if not part:
		bridge_chunks = BridgeBuilder.build(bridges)
	_step(0.82, "lots")
	parking_lots = ParkingLotBuilder.load_lots(dir, graph)
	parking_chunks = ParkingLotBuilder.by_chunk(parking_lots, RoadGeometry.CHUNK_SIZE_M)
	_step(0.84, "yards")
	yard_chunks = YardBuilder.by_chunk(YardBuilder.load_yards(dir), RoadGeometry.CHUNK_SIZE_M)
	_step(0.86, "trees and places")
	# Garages after the surface lots' chunks: their stalls join parking_lots (for parked cars)
	# but are drawn by GarageBuilder at floor height, not draped on the terrain.
	vegetation_chunks = VegetationBuilder.load_by_chunk(dir, RoadGeometry.CHUNK_SIZE_M)
	VegetationBuilder.read_preset()
	green_areas = VegetationBuilder.load_areas(dir)
	services = Services.load_places(dir)
	turfs = Turf.load_all(dir)
	for t in turfs:
		# The turf's centre is a place on the maps (kind "turf"), beside the services.
		var p := Services.Place.new()
		p.id = "turf:" + t.id
		p.kind = "turf"
		p.name = t.name
		var hit := graph.nearest_edge(Vector3(t.centre.x, 0.0, t.centre.y), 200.0)
		var y: float = float((hit["point"] as Vector3).y) if hit.has("point") else 0.0
		p.at = Vector3(t.centre.x, y, t.centre.y)
		p.road_node = ""
		p.address = ""
		services.append(p)
	_step(0.9, "garages")
	garages = GarageBuilder.load_garages(dir, graph)
	if not part:
		var built := GarageBuilder.build(garages)
		garage_chunks = built["structure"]
		garage_light_chunks = built["lights"]
	garage_material = GarageBuilder.material()
	garage_light_material = GarageBuilder.light_material()
	GarageBuilder.clear_ramps(parking_lots, garages)  # no surface stall on a ramp cut
	for g in garages:
		if g.lot != null:
			parking_lots.append(g.lot)
	if not part:
		var garage_holes := GarageBuilder.holes_by_chunk(garages)
		for coord: Vector2i in garage_holes:
			if not terrain_holes.has(coord):
				terrain_holes[coord] = []
			(terrain_holes[coord] as Array).append_array(garage_holes[coord])
	_step(1.0, "done")
	return terrain_index.size() > 0


var _label: String = ""  # the district a part's progress text names
var _graph_dict: Dictionary = {}  # a district of a set keeps its parsed road graph for the join


## [text, ms] for each load step, in order: how long the step before it took (the loading bar's
## steps, timed; the testbed prints them).
var step_times: Array = []
var _step_at_us: int = 0


func _step(fraction: float, text: String) -> void:
	var to := _sink if _sink != null else self
	var now := Time.get_ticks_usec()
	if to._step_at_us != 0:
		to.step_times.append([to.progress_text, (now - to._step_at_us) / 1000.0])
	to._step_at_us = now
	to.progress = _span.x + fraction * (_span.y - _span.x)
	to.progress_text = (_label + ": " + text) if _label != "" else text


## Loads neighbouring districts of one city as one map (add-district-stitching): each loads
## as on its own, then the map takes the joined road graph (DistrictSet.merge_graphs, its
## junctions, markings and footways rebuilt), each terrain chunk from the district owning it,
## and each building, barrier, bridge, lot, garage and place from the district holding its
## centre (each district's files run a little past its border). Roadblocks where crossings
## joined go. One directory loads as `load`. False, with `set_refusal`, when they don't fit.
func load_districts(dirs: PackedStringArray) -> bool:
	set_refusal = ""
	step_times = []
	_step_at_us = 0
	if dirs.size() == 1:
		return self.load(dirs[0])
	if dirs.is_empty():
		return false
	var parts: Array[MapPack] = []
	var manifests: Array = []
	var share := 0.75 / dirs.size()  # each district's own load; the join takes the rest
	for d in dirs:
		var p := MapPack.new()
		p._sink = self
		p._span = Vector2(parts.size() * share, (parts.size() + 1) * share)
		p._label = d.get_file()
		if not p.load(d):
			set_refusal = "%s did not load" % d
			return false
		parts.append(p)
		manifests.append(p.manifest)
	set_refusal = DistrictSet.refusal(manifests)
	if set_refusal != "":
		push_error("MapPack: districts can't be played together: %s" % set_refusal)
		return false
	var rects: Array[Rect2i] = []
	for m: Dictionary in manifests:
		rects.append(DistrictSet.border_rect(m["map"]["border"]))
	var graphs: Array = []
	var borders: Array = []
	for k in range(dirs.size()):
		graphs.append(parts[k]._graph_dict)  # read once, by the district's own load
		borders.append(_read_json(dirs[k].path_join("border.v0.json")))
	_step(0.75, "joining the districts")
	var merged := DistrictSet.merge_graphs(graphs, borders, rects)
	joined_crossings = int(merged["pairs"])
	var base: MapPack = parts[0]
	pack_dir = base.pack_dir
	_content_hash = ""
	manifest = base.manifest.duplicate(true)
	districts = PackedStringArray()
	ads = []
	for p in parts:
		districts.append(str(p.manifest.get("id", "")))
		ads.append_array(p.ads)
	manifest["districts"] = Array(districts)
	graph = RoadGraph.from_dict(merged["graph"])
	junctions = JunctionBuilder.build_all(graph)
	road_material = base.road_material
	terrain_material = base.terrain_material
	water_material = base.water_material
	marking_material = base.marking_material
	building_material = base.building_material
	sidewalk_material = base.sidewalk_material
	barrier_material = base.barrier_material
	bridge_material = base.bridge_material
	garage_material = base.garage_material
	garage_light_material = base.garage_light_material
	marking_visible_to_m = base.marking_visible_to_m
	# Terrain: each chunk from its owner, read from that district's folder.
	terrain_index = base.terrain_index.duplicate(true)
	var chunks: Array = []
	for k in range(parts.size()):
		for entry: Dictionary in parts[k].terrain_index.get("chunks", []):
			if DistrictSet.owner_of(Vector2i(int(entry["cx"]), int(entry["cz"])), rects) == k:
				var e := entry.duplicate()
				e["dir"] = parts[k].pack_dir
				chunks.append(e)
	terrain_index["chunks"] = chunks
	_height_chunks.clear()
	water_polygons = []
	var seen_water := {}
	for p in parts:
		for w in p.water_polygons:
			if not seen_water.has(w.id):
				seen_water[w.id] = true
				water_polygons.append(w)
	water_chunks = _owned_chunks(parts, rects, func(p: MapPack) -> Dictionary: return p.water_chunks)
	vegetation_chunks = _owned_chunks(parts, rects, func(p: MapPack) -> Dictionary: return p.vegetation_chunks)
	yard_chunks = _owned_chunks(parts, rects, func(p: MapPack) -> Dictionary: return p.yard_chunks)
	var markings := MarkingBuilder.new()
	marking_chunks = markings.build(graph, junctions) if markings.load_rules() else {}
	# A building on the border is in both districts' files, and one copy may be cut at that
	# district's import edge: keep one per id, the larger, from the district holding its centre.
	var by_id := {}
	for k in range(parts.size()):
		for b in parts[k].buildings:
			if b.rings.is_empty() or _owner_xz(_centre(b.rings[0]), rects) == -1:
				continue
			var area := absf(_area(b.rings[0]))
			if not by_id.has(b.id) or area > float(by_id[b.id][1]):
				by_id[b.id] = [b, area]
	buildings = []
	var building_ids: Array = by_id.keys()
	building_ids.sort()
	for id: String in building_ids:
		buildings.append(by_id[id][0])
	_step(0.85, "joined buildings and sidewalks")
	building_chunks = BuildingBuilder.build(buildings)
	sidewalk_chunks = SidewalkBuilder.build(graph.pedestrian)
	underpass_chunks = UnderpassBuilder.build(graph.pedestrian)
	terrain_holes = UnderpassBuilder.holes_by_chunk(graph.pedestrian)
	barriers = []
	for k in range(parts.size()):
		for bar in parts[k].barriers:
			if bar.points.is_empty() or _owner_xz(Vector2(bar.points[0].x, bar.points[0].z), rects) != k:
				continue
			if bar.kind == "roadblock" and bar.border_side != "" and _at_joined(bar, merged["joined"]):
				continue  # the road carries on into the next district here
			barriers.append(bar)
	barrier_chunks = BarrierBuilder.build(barriers)
	bridges = []
	for k in range(parts.size()):
		for br in parts[k].bridges:
			var at := Vector2.ZERO
			if not br.decks.is_empty() and not br.decks[0].points.is_empty():
				at = Vector2(br.decks[0].points[0].x, br.decks[0].points[0].z)
			if _owner_xz(at, rects) == k:
				bridges.append(br)
	bridge_chunks = BridgeBuilder.build(bridges)
	garages = []
	var garage_lots := {}
	for k in range(parts.size()):
		for g in parts[k].garages:
			if g.lot != null:
				garage_lots[g.lot] = true
			var at := _centre(g.outer) if not g.outer.is_empty() else (Vector2(g.ramps[0].start.x, g.ramps[0].start.z) if not g.ramps.is_empty() else Vector2.ZERO)
			if _owner_xz(at, rects) == k:
				garages.append(g)
	parking_lots = []
	for k in range(parts.size()):
		for lot in parts[k].parking_lots:
			if not garage_lots.has(lot) and _owner_xz(lot.bounds.get_center(), rects) == k:
				parking_lots.append(lot)
	parking_chunks = ParkingLotBuilder.by_chunk(parking_lots, RoadGeometry.CHUNK_SIZE_M)
	var built := GarageBuilder.build(garages)
	garage_chunks = built["structure"]
	garage_light_chunks = built["lights"]
	GarageBuilder.clear_ramps(parking_lots, garages)
	for g in garages:
		if g.lot != null:
			parking_lots.append(g.lot)
	var garage_holes := GarageBuilder.holes_by_chunk(garages)
	for coord: Vector2i in garage_holes:
		if not terrain_holes.has(coord):
			terrain_holes[coord] = []
		(terrain_holes[coord] as Array).append_array(garage_holes[coord])
	green_areas = []
	services = []
	turfs = []
	var seen := {}
	for k in range(parts.size()):
		var p: MapPack = parts[k]
		for a: Variant in p.green_areas:
			green_areas.append(a)
		for place in p.services:
			if not seen.has("s:" + place.id) and _owner_xz(Vector2(place.at.x, place.at.z), rects) == k:
				seen["s:" + place.id] = true
				services.append(place)
		for t in p.turfs:
			if not seen.has("t:" + t.id):
				seen["t:" + t.id] = true
				turfs.append(t)
	_step(1.0, "done")
	return not chunks.is_empty()


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## From each district, its chunk-keyed entries for the chunks it owns.
static func _owned_chunks(parts: Array[MapPack], rects: Array[Rect2i], field: Callable) -> Dictionary:
	var out := {}
	for k in range(parts.size()):
		var d: Dictionary = field.call(parts[k])
		for coord: Variant in d:
			if coord is Vector2i and DistrictSet.owner_of(coord, rects) == k:
				out[coord] = d[coord]
	return out


static func _owner_xz(p: Vector2, rects: Array[Rect2i]) -> int:
	return DistrictSet.owner_of(DistrictSet.chunk_of(p.x, p.y), rects)


static func _area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(ring.size()):
		var p := ring[i]
		var q := ring[(i + 1) % ring.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _centre(ring: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in ring:
		c += v
	return c / maxf(ring.size(), 1)


static func _at_joined(bar: BarrierBuilder.Barrier, joined: Array) -> bool:
	for j: Dictionary in joined:
		if not (bar.edge_id in j["edges"]):
			continue
		var at: Vector3 = j["at"]
		var mid := (bar.points[0] + bar.points[bar.points.size() - 1]) * 0.5
		if Vector2(mid.x, mid.z).distance_to(Vector2(at.x, at.z)) < 6.0:
			return true
	return false


## SHA-256 over pack.json plus every file's relative path and contents, for co-op pack
## checks: two regenerated packs with the same file sizes still differ.
static func content_hash(dir: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(dir.path_join("pack.json")))
	for rel in pack_files(dir):
		var bytes := FileAccess.get_file_as_bytes(dir.path_join(rel))
		ctx.update(("%s:%d\n" % [rel, bytes.size()]).to_utf8_buffer())
		ctx.update(bytes)
	return ctx.finish().hex_encode()


## Every file of a pack folder, relative and sorted, leaving out the GLB chunk cache (generated
## locally, it differs per machine).
static func pack_files(dir: String) -> Array[String]:
	var entries: Array[String] = []
	_collect_files(dir, "", entries)
	entries.sort()
	var out: Array[String] = []
	for rel in entries:
		if not rel.begins_with("chunks/"):
			out.append(rel)
	return out


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
	return {"id": str(manifest.get("id", "")), "version": str(manifest.get("version", "")), "hash": cached_content_hash()}


## The loaded pack's content hash, computed on first use and reused. Hashing 27 MB of pack
## files on the main thread was a visible hitch every time the report form opened.
func cached_content_hash() -> String:
	if _content_hash == "":
		_content_hash = content_hash(pack_dir)
		content_hash_runs += 1
	return _content_hash


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
var _height_chunks: Dictionary = {}  # Vector2i -> TerrainBuilder.ChunkHeights, decoded on demand for ground_height


## Terrain height at a local x, z from the pack's heightmaps, with no physics and no chunk
## loaded: the thing to place something on the ground before its chunk has collision.
## Returns NAN outside the pack's chunks.
func ground_height(x: float, z: float) -> float:
	if terrain_index.is_empty():
		return NAN
	var chunk_m := float(int(terrain_index.get("samples_per_chunk", 2)) - 1) * float(terrain_index.get("resolution_m", 1.0))
	if chunk_m <= 0.0:
		return NAN
	var coord := Vector2i(floori(x / chunk_m), floori(z / chunk_m))
	if not _height_chunks.has(coord):
		var found: TerrainBuilder.ChunkHeights = null
		for entry in terrain_index.get("chunks", []):
			if int(entry["cx"]) == coord.x and int(entry["cz"]) == coord.y:
				found = TerrainBuilder.load_chunk(pack_dir, terrain_index, entry)
				break
		_height_chunks[coord] = found
	var heights: TerrainBuilder.ChunkHeights = _height_chunks[coord]
	return heights.sample(x, z) if heights != null else NAN


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
	if vegetation_chunks.has(coord):
		var trunks := VegetationBuilder.add_to_chunk(chunk, vegetation_chunks[coord], near)
		if trunks != null:
			collision_meshes.append(trunks)
	if near and garage_chunks.has(coord):
		var mg: ArrayMesh = garage_chunks[coord].to_mesh()
		chunk.add_child(_mesh_instance("garages_lod0", mg, garage_material, 0.0, ROAD_LOD0_END_M))
		collision_meshes.append(mg)
	if near and garage_light_chunks.has(coord):
		var ml := _mesh_instance("garage_lights", garage_light_chunks[coord].to_mesh(), garage_light_material, 0.0, ROAD_LOD0_END_M)
		ml.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(ml)
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
	# Yards in plain vertex colour (the barrier material): the asphalt grain streaked the hedges.
	if near and yard_chunks.has(coord):
		var yards := YardBuilder.build_chunk(yard_chunks[coord], coord, heights, RoadGeometry.CHUNK_SIZE_M)
		if not (yards["lawns"] as RoadMeshBuilder.ChunkTriangles).is_empty():
			var lawn_mi := _mesh_instance("yards_lod0", (yards["lawns"] as RoadMeshBuilder.ChunkTriangles).to_mesh(), barrier_material, 0.0, YardBuilder.VISIBLE_TO_M)
			lawn_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.add_child(lawn_mi)
		if not (yards["props"] as RoadMeshBuilder.ChunkTriangles).is_empty():
			var myp: ArrayMesh = (yards["props"] as RoadMeshBuilder.ChunkTriangles).to_mesh()
			chunk.add_child(_mesh_instance("yards_props_lod0", myp, barrier_material, 0.0, YardBuilder.VISIBLE_TO_M))
			collision_meshes.append(myp)
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
			label.double_sided = false  # from behind, a blank panel rather than the letters backwards
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
	var veg := node.get_node_or_null("vegetation")
	if veg != null:
		downgrade_chunk(veg)  # its LOD0 MultiMeshes go, LOD1 takes over from the chunk's middle
	for child in node.get_children():
		var n := String(child.name)
		if n in NEAR_ROLES or (n.begins_with("veg_") and n.ends_with("_lod0")):
			node.remove_child(child)
			child.queue_free()
		elif child is GeometryInstance3D and (child as GeometryInstance3D).visibility_range_begin > 0.0 and (child as GeometryInstance3D).visibility_range_begin < TERRAIN_LOD1_END_M:
			(child as GeometryInstance3D).visibility_range_begin = 0.0  # the far mesh now stands in for LOD0
			(child as GeometryInstance3D).visibility_range_begin_margin = 0.0


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


static func _terrain_material() -> ShaderMaterial:
	# One colour, with the weather's wetness and snow as uniforms (terrain.gdshader).
	var m := ShaderMaterial.new()
	m.shader = preload("res://world/terrain/terrain.gdshader")
	m.set_shader_parameter("base_color", TerrainBuilder.TERRAIN_COLOR)
	return m


## The manifest's fixed spawn (`map.spawn`: x, z, heading_deg), or empty when the pack leaves
## the start to the game (add-proving-ground: the district's author chose the start line).
func manifest_spawn() -> Dictionary:
	var m: Variant = manifest.get("map", {})
	var spawn: Variant = m.get("spawn", {}) if m is Dictionary else {}
	return spawn if spawn is Dictionary and spawn.has("x") and spawn.has("z") else {}


## The road nearest a fixed spawn, or an empty hit when there is none.
func _fixed_spawn_hit() -> Dictionary:
	var fixed := manifest_spawn()
	if fixed.is_empty():
		return {}
	return graph.nearest_edge(Vector3(float(fixed["x"]), 0.0, float(fixed["z"])), 60.0)


## The edge the spawn sits on: the road under a fixed spawn, else the westernmost eastbound
## motorway edge of at least SPAWN_MIN_EDGE_M whose start is nearest the map origin, so the
## game starts mid-district rather than on a stub cut by the import bbox.
func spawn_edge() -> RoadGraph.RoadEdge:
	var fixed_hit := _fixed_spawn_hit()
	if not fixed_hit.is_empty():
		return fixed_hit["edge"]
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


## The manifest's fixed spawn when the pack has one (at road height, facing its heading), else a
## sensible spawn on the highway, 20 m into the spawn edge, in the outer lane, facing along it.
func spawn_transform() -> Transform3D:
	var fixed := manifest_spawn()
	if not fixed.is_empty():
		var hit := _fixed_spawn_hit()
		var y := float(hit["point"].y) if not hit.is_empty() else 0.0
		var heading := deg_to_rad(float(fixed.get("heading_deg", 0.0)))
		var forward := Vector3(sin(heading), 0.0, -cos(heading))  # 0 north (-z), 90 east (+x)
		return Transform3D(Basis.looking_at(forward, Vector3.UP), Vector3(float(fixed["x"]), y + 1.0, float(fixed["z"])))
	var best := spawn_edge()
	if best == null:
		return Transform3D(Basis(), Vector3(0, 2, 0))
	var p := RoadGeometry.point_at(best.polyline, 20.0)
	var q := RoadGeometry.point_at(best.polyline, 30.0)
	var forward := (q - p)
	forward.y = 0.0
	forward = forward.normalized()
	var lane_w := best.carriageway_m() / maxf(best.lanes_forward + best.lanes_backward, 1)
	var divider := best.carriageway_offset() + best.carriageway_m() * 0.5 - best.lanes_forward * lane_w
	var right := Vector3(-forward.z, 0.0, forward.x)
	var basis := Basis.looking_at(forward, Vector3.UP)
	# The outer (right-hand) lane, beside the shoulder: the player starts on foot on the shoulder.
	return Transform3D(basis, p + right * (divider + (float(best.lanes_forward) - 0.5) * lane_w) + Vector3(0.0, 1.0, 0.0))
