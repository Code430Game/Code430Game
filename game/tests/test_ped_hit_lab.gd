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
