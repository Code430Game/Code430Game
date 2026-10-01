class_name ChunkStreamer
extends Node
## Streams map chunks around the players.
##
## Approach: every frame the chunks are ranked by distance to the anchors. Chunks within
## NEAR_RADIUS_M are wanted at the NEAR tier (full detail and collision), chunks within
## FAR_RADIUS_M at the FAR tier (distant meshes only), the rest not at all. Missing or
## under-built chunks are built nearest first on worker threads (meshes only, no scene tree
## or physics calls), then added on the main thread a few per frame, where collision is
## created. A NEAR chunk the players leave is downgraded in place; a chunk beyond the far
## radius is freed. build_now builds a ring synchronously so a spawn has ground under it.

const NEAR_RADIUS_M := 700.0
const NEAR_RELEASE_M := 900.0  # hysteresis: downgrade only past this
const FAR_RADIUS_M := 6500.0
const FAR_RELEASE_M := 7000.0
const SPAWN_RING_M := 300.0
const BUILDS_IN_FLIGHT := 3
const ADDS_PER_FRAME := 1  # each add creates collision on the main thread; one keeps the frame smooth

var pack: MapPack
var world: Node3D
var road_result: RoadMeshBuilder.Result
## Positions chunks are kept around (the players). Set each frame by the scene.
var anchors: PackedVector3Array = PackedVector3Array()
var use_glb: bool = false
var stats: Dictionary = {"built": 0, "freed": 0, "downgraded": 0, "failed": 0}

var _entries: Dictionary = {}  # Vector2i -> terrain index entry
var _chunks: Dictionary = {}  # Vector2i -> {"node": Node3D, "tier": int}
var _pending: Dictionary = {}  # Vector2i -> {"task": int, "tier": int}
var _ready: Dictionary = {}  # Vector2i -> parts, built and waiting for the per-frame add cap
var _failed: Dictionary = {}  # Vector2i -> true
var _results: Dictionary = {}  # written by worker threads under _mutex
var _mutex := Mutex.new()


func setup(p: MapPack, w: Node3D) -> void:
	pack = p
	world = w
	road_result = RoadMeshBuilder.build(pack.graph, pack.junctions)
	_entries.clear()
	for entry in pack.terrain_index.get("chunks", []):
		_entries[Vector2i(int(entry["cx"]), int(entry["cz"]))] = entry
	use_glb = GlbChunks.chunks_are_current(pack.pack_dir)
	if not use_glb and DirAccess.dir_exists_absolute(pack.pack_dir.path_join("chunks")):
		push_warning("ChunkStreamer: %s/chunks is stale or unverified; generating meshes" % pack.pack_dir)


func _exit_tree() -> void:
	for coord in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[coord]["task"])
	_pending.clear()
	_mutex.lock()
	for coord in _results.keys():
		if not _results[coord].is_empty():
			_results[coord]["node"].free()
	_results.clear()
	_mutex.unlock()
	for coord in _ready.keys():
		_ready[coord]["node"].free()
	_ready.clear()


## Builds every chunk within `radius` of `position` at the NEAR tier right now, blocking.
## Returns the number built.
func build_now(position: Vector3, radius: float = SPAWN_RING_M) -> int:
	var built := 0
	for coord in _entries.keys():
		if _chunk_distance(coord, position) > radius:
			continue
		var current: Dictionary = _chunks.get(coord, {})
		if not current.is_empty() and int(current["tier"]) >= MapPack.Tier.NEAR:
			continue
		var parts := _build_parts(coord, MapPack.Tier.NEAR)
		if parts.is_empty():
			_failed[coord] = true
			continue
		_add_parts(coord, parts)
		built += 1
	return built


func _process(_delta: float) -> void:
	update()


## One streaming step: collect finished builds, add a few, retire and downgrade, schedule more.
func update() -> void:
	if pack == null or anchors.is_empty():
		return
	_collect_finished()
	_add_ready()
	_retire_and_downgrade()
	_schedule_builds()


## Number of chunks in the scene.
func chunk_count() -> int:
	return _chunks.size()


## Tier of a chunk in the scene, or Tier.NONE.
func tier_of(coord: Vector2i) -> int:
	var c: Dictionary = _chunks.get(coord, {})
	return int(c["tier"]) if not c.is_empty() else MapPack.Tier.NONE


## True while builds are in flight or waiting to be added.
func is_busy() -> bool:
	return not _pending.is_empty() or not _ready.is_empty()


func _wanted_tier(coord: Vector2i) -> int:
	var d := _distance_to_anchors(coord)
	if d <= NEAR_RADIUS_M:
		return MapPack.Tier.NEAR
	if d <= FAR_RADIUS_M:
		return MapPack.Tier.FAR
	return MapPack.Tier.NONE


func _distance_to_anchors(coord: Vector2i) -> float:
	var best := INF
	for a in anchors:
		best = minf(best, _chunk_distance(coord, a))
	return best


static func _chunk_distance(coord: Vector2i, p: Vector3) -> float:
	var s := RoadGeometry.CHUNK_SIZE_M
	var centre := Vector2((coord.x + 0.5) * s, (coord.y + 0.5) * s)
	return centre.distance_to(Vector2(p.x, p.z))


func _schedule_builds() -> void:
	if _pending.size() >= BUILDS_IN_FLIGHT:
		return
	var candidates: Array = []
	for coord in _entries.keys():
		if _pending.has(coord) or _ready.has(coord) or _failed.has(coord):
			continue
		var wanted := _wanted_tier(coord)
		if wanted == MapPack.Tier.NONE or wanted <= tier_of(coord):
			continue
		candidates.append([_distance_to_anchors(coord), coord, wanted])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for c in candidates:
		if _pending.size() >= BUILDS_IN_FLIGHT:
			break
		var coord: Vector2i = c[1]
		var tier: int = c[2]
		var task := WorkerThreadPool.add_task(_build_task.bind(coord, tier), false, "chunk %s" % coord)
		_pending[coord] = {"task": task, "tier": tier}


func _build_task(coord: Vector2i, tier: int) -> void:
	var parts := _build_parts(coord, tier)
	_mutex.lock()
	_results[coord] = parts
	_mutex.unlock()


## Mesh-only build of one chunk at `tier` (thread-safe). Empty when the chunk cannot be built.
func _build_parts(coord: Vector2i, tier: int) -> Dictionary:
	var entry: Dictionary = _entries.get(coord, {})
	if entry.is_empty():
		return {}
	if use_glb:
		var glb := pack.pack_dir.path_join("chunks").path_join("chunk_%d_%d.glb" % [coord.x, coord.y])
		if FileAccess.file_exists(glb):
			var parts := GlbChunks.import_chunk_parts(glb, pack.materials(), tier)
			if not parts.is_empty():
				return parts
	var heights := TerrainBuilder.load_chunk(pack.pack_dir, pack.terrain_index, entry)
	if heights == null:
		return {}
	return pack.build_chunk_meshes(coord, heights, road_result, tier)


func _collect_finished() -> void:
	for coord in _pending.keys():
		var p: Dictionary = _pending[coord]
		if not WorkerThreadPool.is_task_completed(p["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(p["task"])
		_mutex.lock()
		var parts: Dictionary = _results.get(coord, {})
		_results.erase(coord)
		_mutex.unlock()
		_pending.erase(coord)
		if parts.is_empty():
			_failed[coord] = true
			stats["failed"] += 1
		else:
			_ready[coord] = parts


func _add_ready() -> void:
	var added := 0
	for coord in _ready.keys():
		if added >= ADDS_PER_FRAME:
			break
		var parts: Dictionary = _ready[coord]
		_ready.erase(coord)
		if _wanted_tier(coord) == MapPack.Tier.NONE:
			parts["node"].free()  # the players left before it landed
			continue
		_add_parts(coord, parts)
		added += 1


func _add_parts(coord: Vector2i, parts: Dictionary) -> void:
	var old: Dictionary = _chunks.get(coord, {})
	if not old.is_empty() and old["node"] != null:
		world.remove_child(old["node"])
		old["node"].queue_free()
	var node: Node3D = parts["node"]
	if int(parts["tier"]) >= MapPack.Tier.NEAR:
		MapPack.attach_collision(parts)
	world.add_child(node)
	_chunks[coord] = {"node": node, "tier": int(parts["tier"])}
	stats["built"] += 1


func _retire_and_downgrade() -> void:
	for coord in _chunks.keys():
		var c: Dictionary = _chunks[coord]
		var d := _distance_to_anchors(coord)
		if d > FAR_RELEASE_M:
			world.remove_child(c["node"])
			c["node"].queue_free()
			_chunks.erase(coord)
			stats["freed"] += 1
		elif int(c["tier"]) >= MapPack.Tier.NEAR and d > NEAR_RELEASE_M:
			MapPack.downgrade_chunk(c["node"])
			c["tier"] = MapPack.Tier.FAR
			stats["downgraded"] += 1
