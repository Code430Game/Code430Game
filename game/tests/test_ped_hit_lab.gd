extends GdUnitTestSuite
## The pedestrian hit lab: a repeatable hit that reports the car's speed before and after.


func _run_lab() -> PedHitLab:
	var lab: PedHitLab = auto_free(load("res://scenes/ped_hit_lab.tscn").instantiate())
	add_child(lab)
	for i in range(60 * 12):
		if not lab.result.is_empty():
			break
		await get_tree().physics_frame
	return lab


func test_lab_hits_the_walker_and_reports_both_speeds() -> void:
	var lab := await _run_lab()
	assert_bool(lab.result.is_empty()).is_false()
	assert_bool(lab.result["knocked_down"]).is_true()
	assert_float(lab.result["before_kph"]).is_between(46.0, 52.0)
	assert_float(lab.result["lowest_kph"]).is_less_equal(lab.result["before_kph"])


func test_car_keeps_going_and_feels_a_bump() -> void:
	var lab := await _run_lab()
	var hit: Dictionary = lab.result
	remove_child(lab)  # its car and the fallen walker would be on the road ahead
	var baseline: PedHitLab = auto_free(load("res://scenes/ped_hit_lab.tscn").instantiate())
	baseline.with_walker = false
	add_child(baseline)
	for i in range(60 * 12):
		if not baseline.result.is_empty():
			break
		await get_tree().physics_frame
	var extra: float = hit["lost_kph"] - baseline.result["lost_kph"]
	assert_float(hit["lowest_kph"]).is_greater(30.0)  # not a wall
	assert_float(extra).is_between(4.0, 9.0)  # a noticeable bump, about 5 to 8 km/h at 50
	assert_float(hit["person_peak_mps"]).is_greater(5.0)  # thrown, not tipped over
