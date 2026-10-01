extends GdUnitTestSuite
## Streaming tiers around an anchor on the Ottawa pack: spawn ring now, far ring over frames,
## downgrade on leaving, free beyond the far radius.

const PACK_ID := "code430.ottawa-centretown"

var _pack: MapPack
var _world: Node3D
var _streamer: ChunkStreamer


func before_test() -> void:
	var dir := PackLocator.find_pack(PACK_ID)
	assert_str(dir).is_not_empty()
	_pack = MapPack.new()
	assert_bool(_pack.load(dir)).is_true()
	_world = auto_free(Node3D.new())
	add_child(_world)
	_streamer = auto_free(ChunkStreamer.new())
	_streamer.set_process(false)  # tests drive update() themselves
	add_child(_streamer)
	_streamer.setup(_pack, _world)


func _coord_at(p: Vector3) -> Vector2i:
	return RoadGeometry.chunk_of(p)


func test_spawn_ring_is_built_now_with_collision() -> void:
	var spawn := _pack.spawn_transform().origin
	var built := _streamer.build_now(spawn, 300.0)
	assert_int(built).is_between(4, 9)
	var here := _coord_at(spawn)
	assert_int(_streamer.tier_of(here)).is_equal(MapPack.Tier.NEAR)
	var node: Node3D = _world.get_node("chunk_%d_%d" % [here.x, here.y])
	assert_object(node.get_node_or_null("collision")).is_not_null()
	assert_object(node.get_node_or_null("terrain_lod0")).is_not_null()


func test_far_chunks_stream_in_over_frames_without_collision() -> void:
	var spawn := _pack.spawn_transform().origin
	_streamer.build_now(spawn, 300.0)
	_streamer.anchors = PackedVector3Array([spawn])
	var frames := 0
	while _streamer.chunk_count() < 40 and frames < 600:
		_streamer.update()
		await get_tree().process_frame
		frames += 1
	assert_int(_streamer.chunk_count()).is_greater_equal(40)
	# Something far from the spawn is FAR tier: no LOD0 terrain, no collision, but LOD1/LOD2 terrain.
	var far_found := false
	for child in _world.get_children():
		var coord := Vector2i(int(child.name.get_slice("_", 1)), int(child.name.get_slice("_", 2)))
		if _streamer.tier_of(coord) == MapPack.Tier.FAR:
			far_found = true
			assert_object(child.get_node_or_null("collision")).is_null()
			assert_object(child.get_node_or_null("terrain_lod0")).is_null()
			assert_object(child.get_node_or_null("terrain_lod2")).is_not_null()
			break
	assert_bool(far_found).is_true()


func test_leaving_downgrades_and_going_far_frees() -> void:
	var spawn := _pack.spawn_transform().origin
	_streamer.build_now(spawn, 300.0)
	var here := _coord_at(spawn)
	# Move the anchor 1.2 km away: the spawn chunk loses collision but stays as a far chunk.
	_streamer.anchors = PackedVector3Array([spawn + Vector3(1200, 0, 0)])
	_streamer.update()
	assert_int(_streamer.tier_of(here)).is_equal(MapPack.Tier.FAR)
	var node: Node3D = _world.get_node("chunk_%d_%d" % [here.x, here.y])
	assert_object(node.get_node_or_null("collision")).is_null()
	assert_object(node.get_node_or_null("terrain_lod1")).is_not_null()
	# Beyond the far release radius it is freed.
	_streamer.anchors = PackedVector3Array([spawn + Vector3(8000, 0, 0)])
	_streamer.update()
	assert_int(_streamer.tier_of(here)).is_equal(MapPack.Tier.NONE)
	await get_tree().process_frame
	while _streamer.is_busy():
		_streamer.update()
		await get_tree().process_frame


func test_streamed_chunks_get_their_collision_over_frames() -> void:
	var spawn := _pack.spawn_transform().origin
	_streamer.anchors = PackedVector3Array([spawn])
	# No spawn ring: everything streams, so collision arrives through the queue.
	var frames := 0
	while _streamer.chunk_count() < 3 and frames < 600:
		_streamer.update()
		await get_tree().process_frame
		frames += 1
	assert_int(_streamer.chunk_count()).is_greater_equal(3)
	var here := _coord_at(spawn)
	assert_int(_streamer.tier_of(here)).is_equal(MapPack.Tier.NEAR)
	var node: Node3D = _world.get_node("chunk_%d_%d" % [here.x, here.y])
	var body: StaticBody3D = node.get_node("collision")
	for i in range(600):
		_streamer.update()
		await get_tree().process_frame
		if _streamer.collision_pending() == 0 and body.get_child_count() > 0:
			break
	assert_int(_streamer.collision_pending()).is_equal(0)
	assert_int(body.get_child_count()).is_greater(0)
	while _streamer.is_busy():
		_streamer.update()
		await get_tree().process_frame
