extends GdUnitTestSuite
## Parked cars: deterministic fill, occupancy by lot type and hour, per-chunk caps, taking a
## car empties its stall, bodies frozen until a vehicle comes close.


func _lot(id: String, origin: Vector2, extra: Dictionary = {}) -> ParkingLotBuilder.Lot:
	var o := origin
	var d := {"id": id, "kind": "surface", "stall_dir": [1, 0], "ground_y": 0.0, "aisles": [], "entrances": [], "osm_id": 1,
		"rings": [[[o.x, o.y], [o.x + 120, o.y], [o.x + 120, o.y + 20], [o.x, o.y + 20]]]}
	d.merge(extra, true)
	return ParkingLotBuilder.lot_from_dict(d, null)


func _parked(lots: Array, hour: float = 12.0) -> ParkedCars:
	var p: ParkedCars = auto_free(ParkedCars.new())
	p.hour = hour
	add_child(p)
	p.setup(lots)
	return p


func _floor() -> void:
	var floor: StaticBody3D = auto_free(StaticBody3D.new())
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	cs.position.y = -0.5
	floor.add_child(cs)
	add_child(floor)


func test_the_same_hour_fills_the_same_stalls_with_the_same_cars() -> void:
	var lots := [_lot("w1.0", Vector2(0, 0)), _lot("w2.0", Vector2(0, 40))]
	var a := _parked(lots)
	var b := _parked(lots)
	assert_int(a.cars.size()).is_greater(0)
	assert_int(a.cars.size()).is_equal(b.cars.size())
	for i in range(a.cars.size()):
		assert_str(a.cars[i].key).is_equal(b.cars[i].key)
		assert_str(a.cars[i].vehicle_id).is_equal(b.cars[i].vehicle_id)
		assert_object(a.cars[i].color).is_equal(b.cars[i].color)
	for c in a.cars:
		assert_bool(c.vehicle_id in ["bus", "box_truck"]).is_false()


func _share(p: ParkedCars, lot: ParkingLotBuilder.Lot) -> float:
	var n := 0
	for c in p.cars:
		if c.lot == lot:
			n += 1
	return float(n) / lot.stalls.size()


func test_downtown_lots_fill_by_day_and_residential_ones_by_night() -> void:
	var paid := _lot("w1.0", Vector2(0, 0), {"fee": "yes"})
	var home := _lot("w2.0", Vector2(0, 40))
	var noon := _parked([paid, home], 12.0)
	var night := _parked([paid, home], 23.0)
	assert_float(_share(noon, paid)).is_greater(_share(noon, home))
	assert_float(_share(night, home)).is_greater(_share(night, paid))
	assert_float(_share(noon, paid)).is_greater(_share(night, paid))


func test_the_cap_keeps_the_nearest_cars_in_a_chunk() -> void:
	var lot := _lot("w1.0", Vector2(0, 0))
	var p := _parked([lot], 12.0)
	p.occupancy_override = 1.0
	p.fill()
	p.per_chunk_cap = 5
	p.anchors = PackedVector3Array([Vector3(0, 0, 0)])
	var shown := p.visible_cars()
	assert_int(shown.size()).is_equal(5)
	for c in shown:
		assert_float(c.stall.centre.x).is_less(40.0)  # the west end, nearest the player


func test_a_taken_car_leaves_its_stall_empty_for_the_session() -> void:
	_floor()
	var lot := _lot("w1.0", Vector2(0, 0))
	var p := _parked([lot], 12.0)
	p.occupancy_override = 1.0
	p.fill()
	p.anchors = PackedVector3Array([Vector3(lot.stalls[0].centre.x, 0, lot.stalls[0].centre.y)])
	p._update_bodies()
	var first: ParkedCars.Parked = null
	for c in p.cars:
		if c.body != null:
			first = c
			break
	assert_object(first).is_not_null()
	var key := first.key
	var car := p.take(first.body)
	auto_free(car)
	assert_str(str(car.get("vehicle_id"))).is_equal(first.vehicle_id)
	p.fill()  # a new hour block
	for c in p.cars:
		assert_str(c.key).is_not_equal(key)


func test_bodies_are_frozen_until_a_vehicle_comes_close() -> void:
	_floor()
	var lot := _lot("w1.0", Vector2(0, 0))
	var p := _parked([lot], 12.0)
	p.occupancy_override = 1.0
	p.fill()
	var s := lot.stalls[0]
	p.anchors = PackedVector3Array([Vector3(s.centre.x, 0, s.centre.y)])
	await get_tree().physics_frame
	p._update_bodies()
	var with_body := 0
	var target: ParkedCars.Parked = null
	for c in p.cars:
		if c.body != null:
			with_body += 1
			assert_bool(c.body.freeze).is_true()
			if target == null:
				target = c
	assert_int(with_body).is_between(1, p.bodies_max)
	var visitor: VehicleBody3D = auto_free(TrafficManager.DRIVABLE_CAR_SCENE.instantiate())
	add_child(visitor)
	var t := target.transform()
	visitor.global_position = t.origin + t.basis.x * 2.6  # pulled up alongside, inside the sensor
	for i in range(4):
		await get_tree().physics_frame
	p._update_bodies()
	assert_bool(target.body.freeze).is_false()  # dynamic before any contact


func test_a_guest_take_empties_the_stall_on_every_peer() -> void:
	var lots := [_lot("w1.0", Vector2(0, 0))]
	var host := _parked(lots, 12.0)
	var guest := _parked(lots, 12.0)  # the same cars: same seed, same hour
	var key: String = host.cars[0].key
	var announced: Array[String] = []
	host.stall_taken.connect(func(k: String) -> void: announced.append(k))
	var got := host.release_key(key)
	assert_str(str(got["vehicle"])).is_not_empty()
	assert_array(announced).contains_exactly([key])  # the host tells the others
	guest.mark_taken(key)  # what _stall_taken does on each guest
	assert_int(guest.cars.size()).is_equal(host.cars.size())
	for i in range(host.cars.size()):
		assert_str(guest.cars[i].key).is_equal(host.cars[i].key)
	assert_dict(host.release_key(key)).is_empty()  # nothing left to take there
