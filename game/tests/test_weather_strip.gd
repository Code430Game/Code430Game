extends GdUnitTestSuite
## The forecast strip above the minimap reads the weather controller: the state now, what
## follows and the real minutes until it starts, "now" during a change, only the state when
## there is no forecast (human, 2026-10-08: "a weather marker above the map, as if the user
## was looking at a weather app with the upcoming weather").


func _controller(seed: int, start: String = "", pin: bool = false) -> WeatherController:
	var w: WeatherController = auto_free(WeatherController.new())
	add_child(w)
	w.set_process(false)
	w.setup(seed, start, pin)
	return w


func _strip(w: WeatherController) -> WeatherStrip:
	var s: WeatherStrip = auto_free(WeatherStrip.new())
	add_child(s)
	s.weather = w
	s.refresh()
	return s


func test_a_state_draws_its_follower_when_it_starts() -> void:
	var w := _controller(7, "overcast")
	assert_str(w.upcoming).is_not_empty()
	assert_bool(w.states.has(w.upcoming)).is_true()
	var f := w.forecast()
	assert_str(str(f["state"])).is_equal("overcast")
	assert_bool(bool(f["changing"])).is_false()
	assert_float(float(f["seconds_left"])).is_equal_approx(w.duration, 1e-3)


func test_the_strip_names_the_follower_and_counts_real_minutes_down() -> void:
	var w := _controller(7, "overcast")
	w.upcoming = "rain"
	w.duration = 400.0
	w.elapsed = 0.0
	var s := _strip(w)
	assert_str(s.text()).is_equal("Overcast  Rain in 7 min")
	w.step(70.0)  # 330 s left: still 6 whole minutes to wait
	s.refresh()
	assert_str(s.text()).is_equal("Overcast  Rain in 6 min")
	w.elapsed = 370.0  # half a minute left rounds up to 1
	s.refresh()
	assert_str(s.text()).is_equal("Overcast  Rain in 1 min")


func test_a_change_under_way_reads_now() -> void:
	var w := _controller(7, "overcast")
	w.next_state = "rain"
	w.t = 0.3
	var s := _strip(w)
	assert_str(s.text()).is_equal("Overcast  Rain now")
	assert_bool(bool(s.shown["changing"])).is_true()


func test_a_pinned_session_shows_only_the_state() -> void:
	var w := _controller(3, "snow", true)
	assert_str(w.upcoming).is_empty()
	var s := _strip(w)
	assert_str(s.text()).is_equal("Snow")
	assert_bool(s.visible).is_true()


func test_glyphs_follow_the_state() -> void:
	assert_str(WeatherStrip.glyph_for("clear")).is_equal("sun")
	assert_str(WeatherStrip.glyph_for("overcast")).is_equal("cloud")
	assert_str(WeatherStrip.glyph_for("rain")).is_equal("rain")
	assert_str(WeatherStrip.glyph_for("snow")).is_equal("snow")
	assert_str(WeatherStrip.glyph_for("fog")).is_equal("fog")
	assert_int(WeatherStrip.minutes_left(0.0)).is_equal(0)
	assert_int(WeatherStrip.minutes_left(1.0)).is_equal(1)
	assert_int(WeatherStrip.minutes_left(120.0)).is_equal(2)


func test_the_follower_rides_the_snapshot_to_a_guest() -> void:
	var host := _controller(11, "clear")
	host.upcoming = "fog"
	host.duration = 500.0
	host.elapsed = 100.0
	var guest := _controller(1, "clear")
	guest.mirror = true
	guest.apply_snapshot(host.snapshot())
	assert_str(guest.upcoming).is_equal("fog")
	var s := _strip(guest)
	assert_str(s.text()).is_equal("Clear  Fog in 7 min")


func test_no_controller_hides_the_strip() -> void:
	var s: WeatherStrip = auto_free(WeatherStrip.new())
	add_child(s)
	s.refresh()
	assert_bool(s.visible).is_false()
	assert_str(s.text()).is_equal("")
