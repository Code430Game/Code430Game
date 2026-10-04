extends GdUnitTestSuite
## Chip music rendering: pitch, timing, loudness, the loop seam and echo, without an audio device.

const RATE := 22050.0


func _track(channels: Array, tempo: float = 120.0, extra: Dictionary = {}) -> Dictionary:
	var t := {
		"tempo_bpm": tempo, "steps_per_beat": 4,
		"instruments": {
			"lead": {"wave": "pulse", "duty": 0.5, "attack": 0.005, "decay": 0.05, "sustain": 0.8, "release": 0.05},
			"tri": {"wave": "triangle", "attack": 0.005, "decay": 0.05, "sustain": 0.8, "release": 0.05},
			"hat": {"wave": "noise", "attack": 0.001, "decay": 0.03, "sustain": 0.0, "release": 0.02},
		},
		"channels": channels,
	}
	t.merge(extra, true)
	return t


func test_note_frequencies() -> void:
	assert_float(ChipSong.note_hz("A4")).is_equal_approx(440.0, 0.01)
	assert_float(ChipSong.note_hz("C4")).is_equal_approx(261.626, 0.01)
	assert_float(ChipSong.note_hz("A#4")).is_equal_approx(466.164, 0.01)
	assert_float(ChipSong.note_hz("Bb4")).is_equal_approx(466.164, 0.01)
	assert_float(ChipSong.note_hz("C#3")).is_equal_approx(138.591, 0.01)
	assert_float(ChipSong.note_hz("H4")).is_equal(0.0)


func test_tokens() -> void:
	assert_array(ChipSong.parse_token("~")).is_equal(["hold", 0.0, 0.0])
	assert_array(ChipSong.parse_token(".")).is_equal(["rest", 0.0, 0.0])
	var loud := ChipSong.parse_token("G3:15")
	var soft := ChipSong.parse_token("G3:3")
	assert_str(loud[0]).is_equal("note")
	assert_float(loud[2]).is_equal(1.0)
	assert_float(soft[2]).is_equal_approx(0.2, 1e-4)
	assert_str(ChipSong.parse_token("zz")[0]).is_equal("rest")


func test_steps_follow_the_sample_clock() -> void:
	var song := ChipSong.from_dict(_track([{"instrument": "lead", "pattern": "A4 C5"}]), RATE)
	assert_float(song.step_samples).is_equal_approx(RATE * 60.0 / (120.0 * 4.0), 1e-6)
	# Step 1 starts at the first whole sample at or after step_samples (2756.25 -> sample 2757).
	var first_of_step_1 := int(ceil(song.step_samples))
	song.render(first_of_step_1)  # samples 0 .. 2756: still step 0
	assert_float(song.channels[0].hz).is_equal_approx(440.0, 0.01)
	song.render(1)  # sample 2757
	assert_float(song.channels[0].hz).is_equal_approx(ChipSong.note_hz("C5"), 0.01)
	assert_float(song.length_s()).is_equal_approx(2 * 60.0 / (120.0 * 4.0), 1e-6)


func test_pulse_pitch_is_right() -> void:
	var held := "A4" + " ~".repeat(31)
	var song := ChipSong.from_dict(_track([{"instrument": "lead", "pattern": held}], 60.0), RATE)
	song.render(int(RATE * 0.1))  # past the attack
	var buf := song.render(int(RATE))
	var crossings := 0
	for i in range(1, buf.size()):
		if (buf[i - 1].x < 0.0) != (buf[i].x < 0.0):
			crossings += 1
	assert_float(crossings / 2.0).is_equal_approx(440.0, 5.0)


func test_dense_track_stays_under_the_clip_ceiling() -> void:
	var lead := "C5:15 E5:15 G5:15 C6:15 ".repeat(8)
	var song := ChipSong.from_dict(_track([
		{"instrument": "lead", "pattern": lead.strip_edges()},
		{"instrument": "lead", "pattern": "C4:15 ~ G4:15 ~ ".repeat(8).strip_edges()},
		{"instrument": "tri", "pattern": "C3:15 ~ ~ ~ ".repeat(8).strip_edges()},
		{"instrument": "hat", "pattern": "C6:15 . C6:15 . ".repeat(8).strip_edges()},
	]), RATE)
	var buf := song.render(song.loop_samples())
	var peak := 0.0
	var sum := 0.0
	for v in buf:
		peak = maxf(peak, absf(v.x))
		sum += v.x * v.x
	var rms := sqrt(sum / buf.size())
	assert_float(peak).is_less_equal(1.0)
	assert_float(rms).is_between(0.05, 0.5)


func test_loop_seam_has_no_envelope_jump() -> void:
	# A note held across the loop point and a bass that restarts on it: both must glide.
	var song := ChipSong.from_dict(_track([
		{"instrument": "lead", "pattern": "C5 ~ ~ ~ E5 ~ ~ ~"},
		{"instrument": "tri", "pattern": "C3 ~ G2 ~ C3 ~ G2 ~"},
	]), RATE)
	var max_step := 1.0 / (RATE * 0.005)  # the fastest envelope slope in this track (5 ms attack)
	song.render(song.loop_samples() - 50)
	var before := song.levels()
	for i in range(100):
		song.render(1)
		var now := song.levels()
		for c in range(now.size()):
			assert_float(absf(now[c] - before[c])).is_less_equal(max_step + 1e-4)
		before = now


func test_echo_repeats_a_note_later() -> void:
	var song := ChipSong.from_dict(_track([{"instrument": "lead", "pattern": "A4 . . . . . . . . . . . . . . ."}], 120.0, {"echo": {"delay_s": 0.5, "gain": 0.4}}), RATE)
	var buf := song.render(int(RATE * 0.8))
	var late := 0.0
	for i in range(int(RATE * 0.55), int(RATE * 0.6)):
		late = maxf(late, absf(buf[i].x))
	assert_float(late).is_greater(0.01)  # the dry note ended long before; this is the echo
