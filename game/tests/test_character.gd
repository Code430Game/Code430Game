extends GdUnitTestSuite
## Character profile, store, mesh and the creator screen.

const CREATOR_SCENE := preload("res://ui/character/character_creator.tscn")

var _path: String


func before_test() -> void:
	_path = "user://tmp/characters_%d.json" % Time.get_ticks_usec()


func after_test() -> void:
	get_tree().paused = false
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


func _joy(button: int) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame


func test_random_profiles_are_normalised_and_step_wraps_or_clamps() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var p := CharacterProfile.random(rng)
	for key: String in CharacterProfile.FIELDS:
		assert_bool(p.has(key)).override_failure_message("missing " + key).is_true()
	assert_bool(CharacterProfile.equals(p, CharacterProfile.normalise(p))).is_true()
	var q := CharacterProfile.step({"top": 0}, "top", -1)
	assert_int(q["top"]).is_equal(CharacterProfile.CLOTH.size() - 1)
	var tall := CharacterProfile.step({"height": CharacterProfile.HEIGHT_MAX}, "height", 3)
	assert_float(tall["height"]).is_equal_approx(CharacterProfile.HEIGHT_MAX, 0.001)
	var junk := CharacterProfile.normalise({"skin": 99, "hair": -4, "height": "tall", "extra": 1})
	assert_int(junk["skin"]).is_equal(CharacterProfile.SKIN.size() - 1)
	assert_int(junk["hair"]).is_equal(0)
	assert_float(junk["height"]).is_equal_approx(1.0, 0.001)
	assert_bool(junk.has("extra")).is_false()


func test_mesh_scales_with_height_and_build() -> void:
	var base := CharacterMesh.build({"hair": 0, "hat": 0, "height": 1.0, "build": 1.0})
	var tall := CharacterMesh.build({"hair": 0, "hat": 0, "height": 1.1, "build": 1.2})
	assert_int(base.get_surface_count()).is_equal(1)
	var a := base.get_aabb()
	var b := tall.get_aabb()
	assert_float(a.position.y).is_equal_approx(0.0, 0.01)
	assert_float(a.size.y).is_between(1.75, 1.85)
	assert_float(b.size.y / a.size.y).is_equal_approx(1.1, 0.01)
	assert_float(b.size.x / a.size.x).is_equal_approx(1.2, 0.01)


func test_store_round_trips_last_and_presets() -> void:
	var first := CharacterStore.last_or_random(_path)
	assert_bool(FileAccess.file_exists(_path)).is_true()
	var again := CharacterStore.last_or_random(_path)
	assert_bool(CharacterProfile.equals(first, again)).is_true()
	var p := CharacterProfile.step(first, "top", 1)
	assert_str(CharacterStore.save_preset(p, "", _path)).is_equal("Character 1")
	assert_str(CharacterStore.save_preset(first, "", _path)).is_equal("Character 2")
	assert_str(CharacterStore.save_preset(first, "Character 1", _path)).is_equal("Character 1")
	assert_int(CharacterStore.presets(_path).size()).is_equal(2)
	assert_bool(CharacterStore.delete_preset("Character 2", _path)).is_true()
	assert_bool(CharacterStore.delete_preset("Character 2", _path)).is_false()
	CharacterStore.save_last(p, _path)
	assert_bool(CharacterProfile.equals(CharacterStore.load_file(_path)["last"], p)).is_true()


func test_remote_player_wears_a_profile() -> void:
	var r: RemotePlayer = auto_free(RemotePlayer.new())
	add_child(r)
	r.setup(2, Color.BLUE, {"top": 3})
	assert_object(r._body.mesh).is_instanceof(ArrayMesh)
	assert_float(r._body.position.y).is_equal_approx(0.0, 0.001)
	r.apply_profile({})
	assert_object(r._body.mesh).is_instanceof(CapsuleMesh)


func test_creator_changes_the_profile_live_and_saves_last_on_done() -> void:
	var creator: CharacterCreator = auto_free(CREATOR_SCENE.instantiate())
	creator.store_path = _path
	add_child(creator)
	var live: Array = []
	creator.profile_changed.connect(func(p: Dictionary) -> void: live.append(p))
	var done: Array = []
	creator.closed.connect(func(p: Dictionary) -> void: done.append(p))
	creator.open({"skin": 2, "top": 0})
	await get_tree().process_frame
	assert_bool(get_tree().paused).is_true()
	await _joy(JOY_BUTTON_DPAD_RIGHT)  # skin 2 -> 3 on the first row
	await _joy(JOY_BUTTON_DPAD_DOWN)
	await _joy(JOY_BUTTON_DPAD_DOWN)
	await _joy(JOY_BUTTON_DPAD_DOWN)
	await _joy(JOY_BUTTON_DPAD_LEFT)  # top 0 -> last colour
	assert_int(creator.profile["skin"]).is_equal(3)
	assert_int(creator.profile["top"]).is_equal(CharacterProfile.CLOTH.size() - 1)
	assert_int(live.size()).is_greater_equal(3)
	await _joy(JOY_BUTTON_B)
	await get_tree().process_frame
	assert_bool(creator.visible).is_false()
	assert_int(done.size()).is_equal(1)
	assert_bool(CharacterProfile.equals(CharacterStore.load_file(_path)["last"], creator.profile)).is_true()
