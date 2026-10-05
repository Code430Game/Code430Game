extends GdUnitTestSuite
## add-bridge-structures 2.x: bridges are solid from below, still drivable on top, and their
## piers stand clear of the roads underneath.

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
	_streamer.build_now(Vector3(620.0, 67.0, 1016.0), 300.0)


func after() -> void:
	_streamer.free()
	_world.free()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))


func _bridge_with_edge(edge_id: String) -> BridgeBuilder.Bridge:
	for b in _pack.bridges:
		for d in b.decks:
			if d.source == edge_id:
				return b
	return null


func test_the_pack_has_bridges_with_decks_piers_and_ends() -> void:
	assert_int(_pack.bridges.size()).is_greater(20)
	var piers := 0
	for br in _pack.bridges:
		piers += br.piers.size()
	assert_int(piers).is_greater(50)
	var b := _bridge_with_edge("w76726915.0")  # the 417 over Metcalfe (#27): short, no pier needed
	assert_object(b).is_not_null()
	assert_int(b.ends.size()).is_greater_equal(2)


func test_looking_up_from_metcalfe_hits_the_underside_not_the_sky() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var b := _bridge_with_edge("w76726915.0")
	var deck: BridgeBuilder.Deck
	for d in b.decks:
		if d.source == "w76726915.0":
			deck = d
	# The spot on the deck with the most room below it: over Metcalfe, not by the abutment.
	var best := Vector3.ZERO
	var best_gap := 0.0
	for i in range(deck.points.size() - 1):
		for t in [0.25, 0.5, 0.75]:
			var p: Vector3 = deck.points[i].lerp(deck.points[i + 1], t)
			var hit := _ray(Vector3(p.x, p.y - b.depth_m - 0.2, p.z), Vector3(p.x, p.y - 30.0, p.z))
			if not hit.is_empty() and p.y - float(hit["position"].y) > best_gap:
				best_gap = p.y - float(hit["position"].y)
				best = p
	assert_float(best_gap).is_greater(4.0)
	var ground_y := best.y - best_gap
	var up := _ray(Vector3(best.x, ground_y + 0.5, best.z), Vector3(best.x, best.y + 0.5, best.z))
	assert_bool(up.is_empty()).override_failure_message("nothing overhead at %s" % best).is_false()
	assert_float(float(up["position"].y)).is_equal_approx(best.y - b.depth_m, 0.15)
	var down := _ray(Vector3(best.x, best.y + 3.0, best.z), Vector3(best.x, best.y - 3.0, best.z))
	assert_float(float(down["position"].y)).is_equal_approx(best.y, 0.1)  # the road on top, not the slab


func test_piers_stand_clear_of_the_roads_below() -> void:
	var checked := 0
	for b in _pack.bridges:
		var own := {}
		for d in b.decks:
			own[d.source] = true
		for p: Dictionary in b.piers:
			var pos: Vector3 = p["pos"]
			for e: RoadGraph.RoadEdge in _pack.graph.edges.values():
				if own.has(e.id) or e.tunnel:
					continue
				for i in range(e.polyline.size() - 1):
					var a: Vector3 = e.polyline[i]
					var c: Vector3 = e.polyline[i + 1]
					var q := Geometry2D.get_closest_point_to_segment(Vector2(pos.x, pos.z), Vector2(a.x, a.z), Vector2(c.x, c.z))
					var d := q.distance_to(Vector2(pos.x, pos.z))
					var y := lerpf(a.y, c.y, Vector2(a.x, a.z).distance_to(q) / maxf(Vector2(a.x, a.z).distance_to(Vector2(c.x, c.z)), 0.001))
					if y < pos.y - 1.0:
						assert_float(d).override_failure_message("%s pier at (%.0f, %.0f) is %.1f m from %s" % [b.id, pos.x, pos.z, d, e.id]).is_greater(e.width_m * 0.5 + 1.4)
			checked += 1
	assert_int(checked).is_greater(50)
