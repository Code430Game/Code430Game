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
const ADDS_PER_FRAME := 1
## A streamed chunk lands in pieces: its node arrives empty, then its mesh instances a few
## per frame and its collision shapes (built on the worker) one per frame, so no single frame
## carries a whole chunk's GPU upload or shape attach.
const MESHES_PER_FRAME := 2
const SHAPES_PER_FRAME := 1

var pack: MapPack
var world: Node3D
var road_result: RoadMeshBuilder.Result
## Positions chunks are kept around (the players). Set each frame by the scene.
var anchors: PackedVector3Array = PackedVector3Array()
var use_glb: bool = false
var stats: Dictionary = {"built": 0, "freed": 0, "downgraded": 0, "failed": 0}
## Worst and smoothed main-thread costs per frame, in ms: adding a chunk node and creating
## collision shapes. Printed by the benchmark to tell streaming hitches from the rest.
var profile: Dictionary = {"add_max_ms": 0.0, "add_ema_ms": 0.0, "shape_max_ms": 0.0, "shape_ema_ms": 0.0, "slow_frames": 0}

var _entries: Dictionary = {}  # Vector2i -> terrain index entry
var _chunks: Dictionary = {}  # Vector2i -> {"node": Node3D, "tier": int}
var _pending: Dictionary = {}  # Vector2i -> {"task": int, "tier": int}
var _ready: Dictionary = {}  # Vector2i -> parts, built and waiting for the per-frame add cap
var _failed: Dictionary = {}  # Vector2i -> true
var _results: Dictionary = {}  # written by worker threads under _mutex
var _shape_queue: Array = []  # [[StaticBody3D, CollisionShape3D], ...] shapes still to attach
var _mesh_queue: Array = []  # [[Node3D, Node], ...] mesh instances still to add to their chunk
var _mutex := Mutex.new()
## Build chunks on worker threads. Off under the headless (dummy) renderer, as in CI and the
## tests: its mesh storage is not thread-safe, and chunk tasks creating meshes at once
## corrupted it ("Attempting to initialize the wrong RID", "Parameter mem is null", and the
## occasional abort, exit 134, that followed). The real renderers are thread-safe.
var threaded: bool = DisplayServer.get_name() != "headless"


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
	for item in _mesh_queue:
		if is_instance_valid(item[1]) and not (item[1] as Node).is_inside_tree():
			(item[1] as Node).free()
	_mesh_queue.clear()
	for item in _shape_queue:
		if is_instance_valid(item[1]) and not (item[1] as Node).is_inside_tree():
			(item[1] as Node).free()
	_shape_queue.clear()


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
		parts["immediate"] = true  # the spawn ring needs ground under the car this frame
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
	var t0 := Time.get_ticks_usec()
	_add_ready()
	var t1 := Time.get_ticks_usec()
	_create_queued_shapes()
	var t2 := Time.get_ticks_usec()
	_retire_and_downgrade()
	_schedule_builds()
	var add_ms := float(t1 - t0) / 1000.0
	var shape_ms := float(t2 - t1) / 1000.0
	profile["add_max_ms"] = maxf(float(profile["add_max_ms"]), add_ms)
	profile["shape_max_ms"] = maxf(float(profile["shape_max_ms"]), shape_ms)
	profile["add_ema_ms"] = float(profile["add_ema_ms"]) * 0.98 + add_ms * 0.02
	profile["shape_ema_ms"] = float(profile["shape_ema_ms"]) * 0.98 + shape_ms * 0.02
	if add_ms + shape_ms > 8.0:
		profile["slow_frames"] = int(profile["slow_frames"]) + 1


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
	var built_now := 0
	for c in candidates:
		if _pending.size() >= BUILDS_IN_FLIGHT or built_now >= BUILDS_IN_FLIGHT:
			break
		var coord: Vector2i = c[1]
		var tier: int = c[2]
		if not threaded:
			var parts := _build_parts(coord, tier)
			if parts.is_empty():
				_failed[coord] = true
				stats["failed"] += 1
			else:
				_ready[coord] = parts
			built_now += 1
			continue
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
				if tier >= MapPack.Tier.NEAR:
					MapPack.prepare_shapes(parts)
				return parts
	var heights := TerrainBuilder.load_chunk(pack.pack_dir, pack.terrain_index, entry)
	if heights == null:
		return {}
	var parts := pack.build_chunk_meshes(coord, heights, road_result, tier)
	if tier >= MapPack.Tier.NEAR:
		MapPack.prepare_shapes(parts)
	return parts


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
	if parts.get("immediate", false):
		if int(parts["tier"]) >= MapPack.Tier.NEAR:
			MapPack.attach_collision(parts)
	else:
		# Land in pieces: detach the meshes and queue them, then the shapes.
		for child in node.get_children():
			node.remove_child(child)
			_mesh_queue.append([node, child])
		if int(parts["tier"]) >= MapPack.Tier.NEAR:
			_queue_collision(parts)
	world.add_child(node)
	_chunks[coord] = {"node": node, "tier": int(parts["tier"])}
	stats["built"] += 1


## Adds an empty collision body now and queues its prepared shapes for the coming frames.
func _queue_collision(parts: Dictionary) -> void:
	var node: Node3D = parts["node"]
	var body := StaticBody3D.new()
	body.name = "collision"
	node.add_child(body)
	# Triangle lists come from the worker (prepare_shapes); the shapes are made here on the main
	# thread, a few per frame in _create_queued_shapes (the physics server is not thread-safe).
	var faces: Array = parts.get("shape_faces", [])
	if faces.is_empty():
		for m in parts["collision_meshes"]:
			if m != null and m.get_surface_count() > 0:
				faces.append(m.get_faces())
	for f in faces:
		_shape_queue.append([body, f])
	if parts.get("water_mesh") != null:
		node.add_child(MapPack.build_water_floor(parts["water_mesh"]))


func _create_queued_shapes() -> void:
	var added := 0
	while added < MESHES_PER_FRAME and not _mesh_queue.is_empty():
		var item: Array = _mesh_queue.pop_front()
		var parent: Node3D = item[0]
		var child: Node = item[1]
		if not is_instance_valid(parent) or not parent.is_inside_tree():
			if is_instance_valid(child):
				child.free()
			continue
		parent.add_child(child)
		added += 1
	if not _mesh_queue.is_empty():
		return  # meshes first, then collision
	var made := 0
	while made < SHAPES_PER_FRAME and not _shape_queue.is_empty():
		var item: Array = _shape_queue.pop_front()
		var body: StaticBody3D = item[0]
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue  # the chunk was freed or downgraded before its shapes arrived
		var shape := MapPack.shape_from_faces(item[1])
		if shape != null:
			body.add_child(shape)
		made += 1


## Adds every built chunk and attaches every queued mesh and shape now (tests: they sit
## outside the tree until they land, which gdUnit counts as orphan nodes; play keeps spreading them over frames).
func flush() -> void:
	for coord in _ready.keys():  # built chunks waiting their turn are outside the tree too
		var parts: Dictionary = _ready[coord]
		_ready.erase(coord)
		if _wanted_tier(coord) == MapPack.Tier.NONE:
			parts["node"].free()
		else:
			_add_parts(coord, parts)
	while not _mesh_queue.is_empty() or not _shape_queue.is_empty():
		var before := _mesh_queue.size() + _shape_queue.size()
		_create_queued_shapes()
		if _mesh_queue.size() + _shape_queue.size() == before:
			break


## Shapes and meshes still waiting to be attached.
func collision_pending() -> int:
	return _shape_queue.size() + _mesh_queue.size()


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
