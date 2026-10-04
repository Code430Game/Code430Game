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
