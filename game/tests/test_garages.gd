extends GdUnitTestSuite
## add-underground-parking 2.x: ramps from the street with no terrain wall, a door at the foot
## of private ones, a level with stalls and parked cars under public ones.

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
	_streamer.build_now(Vector3(141.0, 68.0, -404.0), 300.0)  # the NAC


func after() -> void:
	_streamer.free()
	_world.free()


func _garage(name: String) -> GarageBuilder.Garage:
	for g in _pack.garages:
		if g.name == name:
			return g
	return null


func _down(p: Vector3, from_above: float = 2.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, from_above, 0), p - Vector3(0, 6.0, 0))
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else NAN


func test_every_entrance_has_a_ramp_and_public_garages_have_stalls() -> void:
	var doors := 0
	var open := 0
	for g in _pack.garages:
		assert_int(g.ramps.size()).is_greater(0)
		if g.tier == "door":
			doors += 1
		else:
			open += 1
			assert_object(g.lot).override_failure_message("%s has no lot" % g.id).is_not_null()
	assert_int(doors).is_greater(50)
	assert_int(open).is_greater(10)
	var nac := _garage("NAC underground parking")
	assert_object(nac).is_not_null()
	assert_int(nac.lot.stalls.size()).is_greater(100)
	assert_object(_garage("Victoria Memorial Museum Building")).is_not_null()


func test_driving_down_the_nac_ramp_meets_no_wall_or_step() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var nac := _garage("NAC underground parking")
	var r: GarageBuilder.Ramp = nac.ramps[0]
	var prev := NAN
	for k in range(1, 20):
		var t := k / 20.0
		var p := r.start.lerp(r.end, t)
		var y := _down(p, 1.5)  # from just above the ramp: terrain over it would be hit first
		assert_float(y).override_failure_message("ramp at %.2f: hit %.2f, ramp %.2f" % [t, y, p.y]).is_equal_approx(p.y, 0.15)
		if not is_nan(prev):
			assert_float(absf(y - prev)).is_less(0.6)  # no step
		prev = y
	var on_floor := _down(Vector3(nac.lot.stalls[0].centre.x, nac.floor_y, nac.lot.stalls[0].centre.y), 1.5)
	assert_float(on_floor).is_equal_approx(nac.floor_y, 0.1)


func test_parked_cars_fill_garage_stalls_at_floor_height() -> void:
	var parked: ParkedCars = auto_free(ParkedCars.new())
	add_child(parked)
	parked.occupancy_override = 1.0
	parked.setup(_pack.parking_lots)
	var nac := _garage("NAC underground parking")
	var in_garage := 0
	for c in parked.cars:
		if c.lot == nac.lot:
			in_garage += 1
			assert_float(c.transform().origin.y).is_equal_approx(nac.floor_y, 0.1)
	assert_int(in_garage).is_equal(nac.lot.stalls.size())


func test_no_surface_stall_sits_on_a_ramp() -> void:
	for lot in _pack.parking_lots:
		if lot.kind == "underground":
			continue
		for s in lot.stalls:
			for g in _pack.garages:
				assert_bool(GarageBuilder._near_ramp(g, s.centre, GarageBuilder.RAMP_WIDTH_M * 0.5)).override_failure_message(
					"stall %s#%d on %s's ramp" % [lot.id, s.index, g.id]).is_false()


## Issue #60: parked cars and a column stood where the ramp meets the floor.
func test_the_floor_past_each_ramp_is_clear_of_stalls_and_columns() -> void:
	for g in _pack.garages:
		if g.tier != "garage":
			continue
		for r in g.ramps:
			var foot := Vector2(r.end.x, r.end.z)
			var on := (foot - Vector2(r.start.x, r.start.z)).normalized()
			for k in range(1, 9):  # the first 8 m off the ramp
				var p := foot + on * float(k)
				for s in g.lot.stalls:
					var corners := ParkingLotBuilder.stall_corners(s)
					assert_bool(Geometry2D.is_point_in_polygon(p, corners)).override_failure_message("%s: stall %d on the landing at %s" % [g.id, s.index, p]).is_false()
				for c in g.columns:
					assert_float(c.distance_to(p)).override_failure_message("%s: column on the landing at %s" % [g.id, p]).is_greater(GarageBuilder.RAMP_WIDTH_M * 0.5)
