extends GdUnitTestSuite
## Driving surfaces collide where they are drawn: no invisible ground above the asphalt (#27:
## under the 417 at Metcalfe the coarse collision terrain rose through the road and lifted cars).

const PACK_ID := "code430.ottawa-centretown"

var _pack: MapPack
var _world: Node3D
var _streamer: ChunkStreamer


func before() -> void:
	_pack = MapPack.new()
	assert_bool(_pack.load(PackLocator.find_pack(PACK_ID))).is_true()
	_world = Node3D.new()
	add_child(_world)
	_streamer = ChunkStreamer.new()
	_streamer.set_process(false)
	add_child(_streamer)
	_streamer.setup(_pack, _world)
	_streamer.build_now(Vector3(620.0, 67.0, 1016.0), 400.0)


func after() -> void:
	_streamer.free()
	_world.free()


func _ground_y(x: float, z: float, from_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - 20.0, z))
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else NAN


func test_metcalfe_under_the_417_has_no_invisible_step() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	# The spots where the report's car sat (road at about 67.4 m); collision was 68.1 to 68.9 m.
	for p: Vector2 in [Vector2(617, 1011), Vector2(617, 1014), Vector2(620, 1014), Vector2(618, 1016)]:
		var y := _ground_y(p.x, p.y, 71.5)
		assert_float(y).override_failure_message("ground at %s is %.2f m" % [p, y]).is_less(67.8)


func test_collision_follows_road_centrelines_near_the_start() -> void:
	await get_tree().physics_frame
	var samples := 0
	var raised := 0
	var worst := ""
	for e: RoadGraph.RoadEdge in _pack.graph.edges.values():
		if e.bridge or e.tunnel:
			continue
		for i in range(e.polyline.size() - 1):
			var a: Vector3 = e.polyline[i]
			var b: Vector3 = e.polyline[i + 1]
			for t in [0.25, 0.5, 0.75]:
				var p := a.lerp(b, t)
				if Vector2(p.x - 620.0, p.z - 1016.0).length() > 250.0:
					continue
				var y := _ground_y(p.x, p.z, p.y + 1.2)  # from just above the road: decks overhead don't count
				if is_nan(y):
					continue
				samples += 1
				if y > p.y + 0.4:
					raised += 1
					worst = "%s at (%.0f, %.0f): %.2f m over" % [e.id, p.x, p.z, y - p.y]
	print("terrain collision: %d of %d road samples raised; last %s" % [raised, samples, worst])
	assert_int(samples).is_greater(500)
	assert_int(raised).override_failure_message("collision above the road: %s" % worst).is_equal(0)  # LOD1 terrain collision had one at (785, 941) too
