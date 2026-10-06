extends GdUnitTestSuite
## The car radio: cycle, memory, rendered loops, playing on entry, pausing on exit, Off, and the
## button only working while driving in play.

const SHORT := {
	"id": "test_loop", "title": "Test", "tempo_bpm": 240, "steps_per_beat": 4,
	"instruments": {"lead": {"wave": "pulse", "duty": 0.5, "attack": 0.005, "decay": 0.05, "sustain": 0.7, "release": 0.05}},
	"channels": [{"instrument": "lead", "pattern": "C5 E5 G5 C6 G5 E5 C5 ~"}],
}

var _cfg: String
var _cache: String
var _radio: Radio


func before_test() -> void:
	_cfg = "user://tmp/radio_%d.cfg" % Time.get_ticks_usec()
	_cache = "user://tmp/radio_cache_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tmp"))
	_radio = _make()


func after_test() -> void:
	get_tree().paused = false
	if FileAccess.file_exists(_cfg):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg))
	var dir := ProjectSettings.globalize_path(_cache)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func _make() -> Radio:
	var r: Radio = auto_free(Radio.new())
	r.settings_path = _cfg
	r.cache_dir = _cache
	add_child(r)
	return r


## Points every station at the short test loop so renders take milliseconds.
func _use_short_loop(r: Radio) -> void:
	r.tracks["test_loop"] = SHORT
	for s in r.stations:
		s["variants"]["fallback"]["track"] = "test_loop"


func _await_render(r: Radio, track_id: String) -> void:
	r.request_render(track_id)
	for i in range(300):
		if r.stream_for(track_id) != null:
			return
		await get_tree().process_frame


func test_cycle_is_five_stations_then_off() -> void:
	var ids := _radio.cycle_ids()
	assert_int(ids.size()).is_equal(6)
	assert_str(ids[5]).is_equal(Radio.OFF)
	assert_str(_radio.variant(ids[0])["name"]).is_equal("Hilltop FM")
	assert_str(_radio.variant(ids[1])["name"]).is_equal("Redline FM")
	assert_str(_radio.variant(ids[4])["name"]).is_equal("Chatter AM")
	_radio.select(ids[4])
	_radio.cycle(1)
	assert_str(_radio.station_id).is_equal(Radio.OFF)
	_radio.cycle(1)
	assert_str(_radio.station_id).is_equal(ids[0])  # wraps


func test_station_and_volume_are_remembered() -> void:
	_radio.select("code430.base.crypt")
	_radio.set_music_volume_db(-12.0)
	var again := _make()
	assert_str(again.station_id).is_equal("code430.base.crypt")
	assert_float(again.music_volume_db).is_equal(-12.0)


func test_rendered_loop_is_one_seamless_pass() -> void:
	var wav := Radio.render_loop(SHORT)
	var song := ChipSong.from_dict(SHORT)
	assert_int(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(wav.loop_end).is_equal(song.loop_samples())
	assert_int(wav.data.size()).is_equal(song.loop_samples() * 2)


func test_plays_on_entry_pauses_on_exit_and_resumes() -> void:
	_use_short_loop(_radio)
	await _await_render(_radio, "test_loop")
	assert_bool(_radio.is_playing()).is_false()  # not driving yet
	_radio.car_entered()
	assert_bool(_radio.is_playing()).is_true()
	_radio.car_exited()
	assert_bool(_radio.is_playing()).is_false()
	_radio.car_entered()
	assert_bool(_radio.is_playing()).is_true()


## A stand-in for a drivable car: only the field the radio reads and writes.
class FakeCar:
	extends Node
	var radio_station: String = ""


func test_the_first_car_takes_the_players_choice_and_the_dial_writes_back() -> void:
	_radio.select("code430.base.quest")
	var mine: FakeCar = auto_free(FakeCar.new())
	_radio.car_entered(mine)
	assert_str(mine.radio_station).is_equal("code430.base.quest")
	_radio.cycle(1)
	assert_str(mine.radio_station).is_equal("code430.base.crypt")
	_radio.car_exited()
	_radio.cycle(1)  # not driving: the car keeps what it had
	assert_str(mine.radio_station).is_equal("code430.base.crypt")


func test_swapping_cars_keeps_each_cars_station() -> void:
	_radio.select("code430.base.redline")
	var mine: FakeCar = auto_free(FakeCar.new())
	_radio.car_entered(mine)
	_radio.car_exited()
	var taken: FakeCar = auto_free(FakeCar.new())
	taken.radio_station = "code430.base.hilltop"  # its owner's station
	_radio.car_entered(taken)
	assert_str(_radio.station_id).is_equal("code430.base.hilltop")
	assert_str(_make().station_id).is_equal("code430.base.redline")  # getting in is not a choice: not saved
	_radio.car_exited()
	_radio.car_entered(mine)
	assert_str(_radio.station_id).is_equal("code430.base.redline")
	assert_str(taken.radio_station).is_equal("code430.base.hilltop")


func test_a_car_left_off_stays_off_and_an_unknown_station_falls_back() -> void:
	_radio.select("code430.base.crypt")
	var quiet: FakeCar = auto_free(FakeCar.new())
	quiet.radio_station = Radio.OFF
	_radio.car_entered(quiet)
	assert_str(_radio.station_id).is_equal(Radio.OFF)
	assert_bool(_radio.is_playing()).is_false()
	_radio.car_exited()
	var stale: FakeCar = auto_free(FakeCar.new())
	stale.radio_station = "gone.station"  # from a pack no longer loaded
	_radio.car_entered(stale)
	assert_str(stale.radio_station).is_equal("code430.base.crypt")


func test_picks_are_seeded_sometimes_off_and_emergency_is_talk_or_nothing() -> void:
	var ids := Radio.station_ids()
	assert_int(ids.size()).is_equal(5)
	var seen := {}
	for i in range(200):
		var got := Radio.pick_for_car(i)
		assert_str(got).is_equal(Radio.pick_for_car(i))  # the same car, the same station
		assert_bool(got == Radio.OFF or ids.has(got)).is_true()
		seen[got] = true
	assert_int(seen.size()).is_equal(6)  # every station and off turn up
	var emergency := {}
	for i in range(100):
		emergency[Radio.pick_for_car(i, true)] = true
	assert_array(emergency.keys()).contains_exactly_in_any_order([Radio.CHATTER, Radio.OFF])


func test_off_is_silent() -> void:
	_use_short_loop(_radio)
	await _await_render(_radio, "test_loop")
	_radio.car_entered()
	_radio.select(Radio.OFF)
	assert_bool(_radio.is_playing()).is_false()
	_radio.cycle(1)  # back to the first station
	assert_bool(_radio.is_playing()).is_true()


func test_station_waits_for_its_render_then_plays() -> void:
	_use_short_loop(_radio)
	_radio.car_entered()  # not rendered yet: nothing to play
	for i in range(300):
		if _radio.is_playing():
			break
		await get_tree().process_frame
	assert_bool(_radio.is_playing()).override_failure_message("did not start once its loop rendered").is_true()


func _press_radio() -> void:
	var ev := InputEventAction.new()
	ev.action = "radio_cycle"
	ev.pressed = true
	_radio._unhandled_input(ev)


func test_button_only_works_while_driving_in_play() -> void:
	_use_short_loop(_radio)
	var first := _radio.station_id
	_press_radio()  # on foot
	assert_str(_radio.station_id).is_equal(first)
	_radio.car_entered()
	get_tree().paused = true
	_press_radio()  # in a menu
	assert_str(_radio.station_id).is_equal(first)
	get_tree().paused = false
	_press_radio()
	assert_str(_radio.station_id).is_not_equal(first)


func test_render_is_cached_and_reused() -> void:
	_use_short_loop(_radio)
	await _await_render(_radio, "test_loop")
	var path := Radio.cache_path(SHORT, _cache)
	assert_bool(FileAccess.file_exists(path)).override_failure_message("no cache file at %s" % path).is_true()
	var cached := Radio.load_cached(SHORT, _cache)
	assert_object(cached).is_not_null()
	assert_int(cached.data.size()).is_equal(_radio.stream_for("test_loop").data.size())
	assert_int(cached.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(cached.loop_end).is_equal(ChipSong.from_dict(SHORT).loop_samples())


func test_changed_track_gets_a_new_cache_file() -> void:
	var changed := SHORT.duplicate(true)
	changed["tempo_bpm"] = 200
	assert_str(Radio.cache_path(changed, _cache)).is_not_equal(Radio.cache_path(SHORT, _cache))


func test_one_render_at_a_time_and_the_playing_station_first() -> void:
	_radio.request_render("questline", false)
	_radio.request_render("deep_crypt", false)
	_radio.request_render("chatter", true)  # urgent: jumps the queue
	# questline started at once (nothing was running); chatter is next, ahead of deep_crypt.
	assert_str(_radio._task_track).is_equal("questline")
	assert_array(_radio._queue).is_equal(["chatter", "deep_crypt"])
	for i in range(1200):
		if not _radio.rendering():
			break
		await get_tree().process_frame
