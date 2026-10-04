extends GdUnitTestSuite
## The traffic hit lab: repeatable crashes between the player's car and traffic.


## Runs a lab scenario to its result and frees the lab (so the next one starts on a clear road).
func _run(scenario: String) -> Dictionary:
	var lab: TrafficHitLab = load("res://scenes/traffic_hit_lab.tscn").instantiate()
	lab.scenario = scenario
	add_child(lab)
	for i in range(60 * 16):
		if not lab.result.is_empty():
			break
		await get_tree().physics_frame
	var result := lab.result.duplicate()
	lab.queue_free()
	await get_tree().physics_frame
	return result


func test_lab_crashes_and_reports() -> void:
	var r := await _run("rear")
	assert_bool(r["contact"]).is_true()
	assert_float(r["before_kph"]).is_between(46.0, 52.0)
	assert_float(r["lowest_kph"]).is_less(r["before_kph"])


func test_rear_ending_traffic_shares_momentum_instead_of_hitting_a_wall() -> void:
	var r := await _run("rear")
	# 1200 kg at 49 km/h into a stopped 1400 kg sedan: about 23 km/h each, not 0.
	assert_float(r["after_kph"]).is_between(15.0, 32.0)
	assert_int(r["frozen_contacts"]).is_equal(0)


func test_traffic_driving_into_a_parked_car_pushes_it_like_a_car_would() -> void:
	var r := await _run("nudge")
	assert_float(r["peak_car_mps"]).is_less(9.0)  # was 12.4: shoved as if it weighed nothing
	assert_int(r["frozen_contacts"]).is_equal(0)


func test_a_wedged_car_is_never_launched() -> void:
	var r := await _run("wedge")
	assert_float(r["peak_body_mps"]).is_less(6.0)  # was 15 when the lead car snapped back
	assert_float(r["max_height_m"]).is_less(0.8)
	var cap := 25.0  # traffic_config.json separation_cap_mps
	var chain := await _run("chain")
	assert_float(chain["peak_body_mps"]).is_less_equal(cap)
	assert_int(chain["frozen_contacts"]).is_equal(0)
