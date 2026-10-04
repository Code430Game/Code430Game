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


func _chatter() -> Dictionary:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://core/audio/radio/music.v0.json"))
	for t in doc["tracks"]:
		if t["id"] == "chatter":
			return t
	return {}


func test_talk_segments_fit_between_the_jingles() -> void:
	var track := _chatter()
	var song := ChipSong.from_dict(track, RATE)
	var segments: Array = track["talk"]["segments"]
	var bar_s := 60.0 / float(track["tempo_bpm"]) * 4.0
	var second_jingle := 12 * bar_s
	for e in song.talk_events:
		var start := float(e[0]) / RATE
		var end := float(e[1]) / RATE
		if start < float(segments[1]["start_s"]):
			assert_float(end).override_failure_message("segment A runs into the second jingle").is_less(second_jingle)
		else:
			assert_float(end).override_failure_message("segment B runs past the loop").is_less(song.length_s())
	assert_int(song.talk_events.size()).is_greater(100)


func test_question_rises_and_statement_falls() -> void:
	var talk := {"voices": {"v": {"base_hz": 200.0, "range": 6.0, "syllables_per_s": 8.0}},
		"segments": [{"start_s": 0.0, "phrases": [
			{"voice": "v", "text": "ba ko ri ta ne mo?"},
			{"voice": "v", "text": "ba ko ri ta ne mo"}]}]}
	var events := ChipSong.build_talk(talk, RATE, 1)
	assert_int(events.size()).is_equal(12)
	# Question: the last syllable ends well above the first; statement: the reverse.
	assert_float(events[5][6]).is_greater(events[0][5] * pow(2.0, 2.0 / 12.0))
	assert_float(events[11][6]).is_less(events[6][5])


func test_talk_renders_speech_and_silence() -> void:
	var song := ChipSong.from_dict(_chatter(), RATE)
	var e0: Array = song.talk_events[0]
	song.render(e0[0])  # up to the first syllable (the jingle has finished by then)
	var speech := song.render(int(0.4 * RATE))
	var loud := 0.0
	for v in speech:
		loud = maxf(loud, absf(v.x))
	assert_float(loud).is_greater(0.05)
