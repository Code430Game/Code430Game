extends GdUnitTestSuite
## The pure parts of the synthesiser: pitch, gains, noise, and that voices fill their buffers.


func test_engine_pitch_rises_with_speed_and_throttle() -> void:
	var idle := Synth.engine_hz(0.0, 0.0)
	assert_float(idle).is_between(50.0, 60.0)
	assert_float(Synth.engine_hz(4.0, 0.0)).is_greater(idle)
	assert_float(Synth.engine_hz(4.0, 1.0)).is_greater(Synth.engine_hz(4.0, 0.0))
	assert_float(Synth.engine_hz(30.0, 0.0)).is_greater(Synth.engine_hz(12.0, 0.0))


func test_impact_and_tyre_gains_are_clamped() -> void:
	assert_float(Synth.impact_gain(0.5)).is_equal(0.0)
	assert_float(Synth.impact_gain(8.5)).is_equal_approx(0.5, 1e-6)
	assert_float(Synth.impact_gain(50.0)).is_equal(1.0)
	assert_float(Synth.tyre_gain(0.0)).is_equal(0.0)
	assert_float(Synth.tyre_gain(100.0)).is_equal(1.0)
	assert_float(AmbienceAudio.level_for(0)).is_equal_approx(0.25, 1e-6)
	assert_float(AmbienceAudio.level_for(100)).is_equal(1.0)


func test_noise_stays_in_range_and_varies() -> void:
	var state: Array = [12345]
	var lo := 1.0
	var hi := -1.0
	for i in range(1000):
		var n := Synth.noise(state)
		lo = minf(lo, n)
		hi = maxf(hi, n)
	assert_float(lo).is_between(-1.0, -0.5)
	assert_float(hi).is_between(0.5, 1.0)


func test_ambience_voice_fills_its_buffer() -> void:
	var amb: AmbienceAudio = auto_free(AmbienceAudio.new())
	add_child(amb)
	await get_tree().process_frame
	await get_tree().process_frame
	var pb: AudioStreamGeneratorPlayback = amb._player.get_stream_playback()
	assert_object(pb).is_not_null()
	assert_int(pb.get_frames_available()).is_less(int(Synth.MIX_RATE * Synth.BUFFER_S))
