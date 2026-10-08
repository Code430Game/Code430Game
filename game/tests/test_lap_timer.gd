extends GdUnitTestSuite
## The lap timer (add-proving-ground): a crossing starts a lap, the next ends it and keeps the
## best, a reverse does not count, off the loop the readout hides and the lap resets.

var _pack: MapPack
var _timer: LapTimer


func before() -> void:
	var dir := PackLocator.find_pack("code430.proving-ground")
	assert_str(dir).is_not_empty()
	_pack = MapPack.new()
	assert_bool(_pack.load(dir)).is_true()


func before_test() -> void:
	_timer = LapTimer.new()
	assert_bool(_timer.load(_pack.pack_dir)).is_true()


## Drives straight along the vertical from z0 to z1 at x, `seconds` long, in small steps.
func _drive(x: float, z0: float, z1: float, seconds: float) -> void:
	var steps := 20
	for i in range(1, steps + 1):
		var z := lerpf(z0, z1, float(i) / steps)
		_timer.update(Vector3(x, 62.0, z), _pack.graph, seconds / steps)


func test_crossing_the_line_starts_a_lap_and_the_next_crossing_keeps_the_best() -> void:
	_drive(-1.75, -260.0, -200.0, 2.0)  # still north of the line at z = -180
	assert_bool(_timer.visible).is_true()
	assert_float(_timer.current_s).is_equal(-1.0)
	_drive(-1.75, -200.0, -160.0, 2.0)  # over the line
	assert_float(_timer.current_s).is_between(0.0, 1.0)
	assert_str(_timer.readout()).starts_with("LAP  0:0")
	# Pretend a lap of 90 s passed on the loop road, then come back round and cross again.
	_timer.update(Vector3(-1.75, 62.0, -150.0), _pack.graph, 90.0)
	_drive(-1.75, -260.0, -200.0, 1.0)
	_drive(-1.75, -200.0, -160.0, 1.0)
	assert_float(_timer.best_s).is_between(90.0, 95.0)
	assert_float(_timer.last_s).is_between(90.0, 95.0)
	assert_float(_timer.current_s).is_between(0.0, 1.0)
	assert_str(_timer.readout()).contains("BEST 1:3")


func test_a_reverse_over_the_line_does_not_count() -> void:
	_drive(-1.75, -200.0, -160.0, 2.0)
	assert_float(_timer.current_s).is_between(0.0, 1.0)
	# Back up over the line and forward again straight away: within the re-arm time.
	_drive(-1.75, -160.0, -200.0, 1.0)
	_drive(-1.75, -200.0, -160.0, 1.0)
	assert_float(_timer.best_s).is_equal(INF)
	assert_float(_timer.current_s).is_between(2.0, 4.0)


func test_off_the_loop_hides_and_resets() -> void:
	_drive(-1.75, -200.0, -160.0, 2.0)
	assert_bool(_timer.visible).is_true()
	# Into the main city grid, well away from any loop road.
	_timer.update(Vector3(-320.0, 62.0, -270.0), _pack.graph, 0.1)
	assert_bool(_timer.visible).is_false()
	assert_float(_timer.current_s).is_equal(-1.0)
	assert_str(_timer.readout()).starts_with("LAP  --:--.-")


func test_the_street_under_the_viaduct_does_not_end_the_lap() -> void:
	# River Road passes under the viaduct at z = 250; on the deck 6 m above it the player is
	# still on the loop (the autodrive lost its lap here before the level check).
	_drive(-1.75, -200.0, -160.0, 2.0)
	_timer.update(Vector3(-6.0, 68.0, 249.0), _pack.graph, 0.1)
	assert_bool(_timer.visible).is_true()
	assert_float(_timer.current_s).is_greater(0.0)


func test_wide_of_the_line_is_not_a_crossing() -> void:
	# 40 m to the side of the start point, past the line's half width, on no loop road.
	_drive(40.0, -200.0, -160.0, 2.0)
	assert_float(_timer.current_s).is_equal(-1.0)


func test_format_time() -> void:
	assert_str(LapTimer.format_time(0.0)).is_equal("0:00.0")
	assert_str(LapTimer.format_time(91.26)).is_equal("1:31.2")
	assert_str(LapTimer.format_time(600.0)).is_equal("10:00.0")
