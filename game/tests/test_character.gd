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
	assert_int(q["top"]).is_equal(CharacterProfile.palette("cloth").size() - 1)
	var tall := CharacterProfile.step({"height": CharacterProfile.HEIGHT_MAX}, "height", 3)
	assert_float(tall["height"]).is_equal_approx(CharacterProfile.HEIGHT_MAX, 0.001)
	var junk := CharacterProfile.normalise({"skin": 99, "hair": -4, "height": "tall", "extra": 1})
	assert_int(junk["skin"]).is_equal(CharacterProfile.palette("skin").size() - 1)
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


func test_posed_mesh_moves_the_feet_and_skinned_mesh_carries_bones() -> void:
	var rest := CharacterMesh.build({"hair": 0, "hat": 0})
	var stride := CharacterMesh.build({"hair": 0, "hat": 0}, CharacterMesh.walk_pose(PI * 0.5, 1.0))
	assert_float(stride.get_aabb().size.z).is_greater(rest.get_aabb().size.z + 0.2)
	var skinned := CharacterMesh.build({"hair": 0, "hat": 0}, {}, true)
	var arrays := skinned.surface_get_arrays(0)
	assert_int((arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size()).is_equal((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * 4)
	var full := CharacterMesh.build({"hair": 5, "hat": 1, "beard": 2, "glasses": 1, "jacket": 1})
	assert_int(full.get_surface_count()).is_equal(1)


func test_rig_walks_when_moving_and_rests_when_still() -> void:
	var rig: CharacterRig = auto_free(CharacterRig.new())
	add_child(rig)
	assert_int(rig.skeleton.get_bone_count()).is_equal(CharacterMesh.BONES.size())
	rig.set_walk(PI * 0.5, 1.0)
	var thigh := CharacterMesh.bone_index("thigh_l")
	assert_float(rig.skeleton.get_bone_pose_rotation(thigh).get_angle()).is_greater(0.3)
	for i in range(60):
		rig.advance(1.0 / 60.0, 0.0)
	assert_float(rig.amount).is_equal_approx(0.0, 0.001)
	assert_float(rig.skeleton.get_bone_pose_rotation(thigh).get_angle()).is_less(0.01)


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
	assert_object(r._rig).is_not_null()
	assert_object(r._body.mesh).is_null()
	r.apply_profile({})
	assert_object(r._rig).is_null()
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
	assert_int(creator.profile["top"]).is_equal(CharacterProfile.palette("cloth").size() - 1)
	assert_int(live.size()).is_greater_equal(3)
	await _joy(JOY_BUTTON_B)
	await get_tree().process_frame
	assert_bool(creator.visible).is_false()
	assert_int(done.size()).is_equal(1)
	assert_bool(CharacterProfile.equals(CharacterStore.load_file(_path)["last"], creator.profile)).is_true()


func test_knees_bend_backward_and_elbows_forward() -> void:
	# The character faces -Z. Mid-swing the bent knee must put the heel behind the knee (+Z),
	# and the elbow must put the hand in front of the elbow (-Z); the old signs gave bird knees.
	var profile := CharacterProfile.normalise({})
	var pose := CharacterMesh.walk_pose(PI, 1.0)  # left leg mid-swing, shin_l at its peak
	var knee := CharacterMesh.bone_global(CharacterMesh.bone_index("shin_l"), profile, pose)
	var heel := knee * Vector3(0.0, -0.4, 0.0)
	assert_float(heel.z - knee.origin.z).is_greater(0.05)
	var elbow := CharacterMesh.bone_global(CharacterMesh.bone_index("forearm_l"), profile, pose)
	var hand := elbow * Vector3(0.0, -0.25, 0.0)
	assert_float(hand.z - elbow.origin.z).is_less(-0.02)


func test_jacket_is_open_over_the_shirt() -> void:
	# In the chest band, down the front centre line only the shirt colour shows, and the
	# jacket colour sits further forward than the shirt does: an open coat over a full shirt.
	var profile := {"hair": 0, "hat": 0, "beard": 0, "glasses": 0, "jacket": 1, "top": 0, "bottom": 5, "jacket_colour": 3, "height": 1.0, "build": 1.0}
	var mesh := CharacterMesh.build(profile)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var shirt: Color = CharacterProfile.CLOTH[0]
	var coat: Color = CharacterProfile.CLOTH[3]
	assert_bool(shirt.is_equal_approx(coat)).is_false()
	var aabb := mesh.get_aabb()
	var y0 := aabb.position.y + aabb.size.y * 0.52
	var y1 := aabb.position.y + aabb.size.y * 0.72
	var shirt_front := 0
	var coat_front_centre := 0
	var coat_outer := 0.0
	var shirt_outer := 0.0
	for i in range(verts.size()):
		var v := verts[i]
		if v.y < y0 or v.y > y1:
			continue
		var centre := absf(v.x) < aabb.size.x * 0.04
		if _same_colour(cols[i], shirt):
			shirt_outer = maxf(shirt_outer, -v.z)
			if centre and v.z < 0.0:
				shirt_front += 1
		elif _same_colour(cols[i], coat):
			coat_outer = maxf(coat_outer, -v.z)
			if centre and v.z < 0.0:
				coat_front_centre += 1
	assert_int(shirt_front).is_greater(0)
	assert_int(coat_front_centre).is_equal(0)
	assert_float(coat_outer).is_greater(shirt_outer)


func test_jacket_front_opens_wide_enough_not_to_read_as_a_tie() -> void:
	# An 8 cm gap between the fronts passed the test above but still read as a tie on the Deck
	# (human, 2026-10-02): no jacket colour on the front within 10 cm of the centre line.
	var profile := {"hair": 0, "hat": 0, "beard": 0, "glasses": 0, "jacket": 1, "top": 0, "bottom": 5, "jacket_colour": 3, "height": 1.0, "build": 1.0}
	var arrays := CharacterMesh.build(profile).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var coat: Color = CharacterProfile.CLOTH[3]
	var nearest := INF
	for i in range(verts.size()):
		var v := verts[i]
		# The fronts' outer face (z -0.14); the collar's front at -0.13 crosses the centre by design.
		if v.z < -0.135 and v.y > 0.9 and v.y < 1.4 and _same_colour(cols[i], coat):
			nearest = minf(nearest, absf(v.x))
	assert_float(nearest).is_less(INF)
	assert_float(nearest).is_greater_equal(0.10)


## Vertex colours come back quantised to 8 bits, so compare loosely.
static func _same_colour(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


## add-pack-loader 3.1: the enabled character pack's palettes replace the built-ins, keeping
## the built-in colours first so a saved character still looks right; with the pack disabled
## the built-ins return, and the creator lists the pack's presets under the player's own.
func test_character_pack_palettes_extend_the_built_ins_and_fall_back_when_disabled() -> void:
	var saved_dirs := PackLoader.search_dirs
	var saved_path := PackLoader.enabled_path
	var saved_map := PackLoader.active_map
	PackLoader.enabled_path = "user://tmp/packs_char_%d.cfg" % Time.get_ticks_usec()
	PackLoader.search_dirs = PackedStringArray([ProjectSettings.globalize_path("res://").path_join("../packs").simplify_path()])
	PackLoader.active_map = "code430.ottawa-centretown"
	PackLoader.reload()
	assert_bool(PackLoader.loaded_ids.has("code430.characters")).is_true()
	var cloth := CharacterProfile.palette("cloth")
	assert_int(cloth.size()).is_greater(CharacterProfile.CLOTH.size())
	for i in range(CharacterProfile.CLOTH.size()):
		assert_bool(cloth[i].is_equal_approx(CharacterProfile.CLOTH[i])).override_failure_message("cloth %d changed" % i).is_true()
	assert_str(CharacterProfile.palette_source()).is_equal("code430.characters:palettes.v1.json")
	assert_str(CharacterProfile.label({"top": 10}, "top")).is_equal("navy")
	var nowhere := "user://tmp/no_such_characters_%d.json" % Time.get_ticks_usec()
	var presets := CharacterCreator.all_presets(nowhere)
	assert_int(presets.size()).is_equal(6)
	assert_str(str((presets[0] as Dictionary)["pack_id"])).is_equal("code430.characters")
	var mesh := CharacterMesh.build((presets[0] as Dictionary)["profile"])
	assert_int(mesh.get_surface_count()).is_equal(1)
	PackLoader.set_enabled("code430.characters", false)
	PackLoader.reload()
	assert_int(CharacterProfile.palette("cloth").size()).is_equal(CharacterProfile.CLOTH.size())
	assert_str(CharacterProfile.palette_source()).is_empty()
	assert_str(CharacterProfile.label({"top": 10}, "top")).is_equal("teal")  # clamped to the built-in list
	assert_int(CharacterCreator.all_presets(nowhere).size()).is_equal(0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PackLoader.enabled_path))
	PackLoader.search_dirs = saved_dirs
	PackLoader.enabled_path = saved_path
	PackLoader.active_map = saved_map
	PackLoader.reload()


func test_hair_stops_above_the_eyes_and_shirt_stops_at_the_waist() -> void:
	var profile := {"hair": 2, "hair_colour": 0, "hat": 0, "beard": 0, "glasses": 0, "jacket": 0, "top": 0, "bottom": 2, "height": 1.0, "build": 1.0}
	var mesh := CharacterMesh.build(profile)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var hair: Color = CharacterProfile.HAIR_COLOUR[0]
	var shirt: Color = CharacterProfile.CLOTH[0]
	var trousers: Color = CharacterProfile.CLOTH[2]
	var hair_front_low := 10.0
	var shirt_low := 10.0
	var trousers_high := 0.0
	for i in range(verts.size()):
		var v := verts[i]
		var torso := absf(v.x) < 0.15  # sleeves are shirt-coloured too; measure the body only
		if _same_colour(cols[i], hair) and v.z < -0.08 and v.y > 1.4:
			hair_front_low = minf(hair_front_low, v.y)
		elif _same_colour(cols[i], shirt) and torso:
			shirt_low = minf(shirt_low, v.y)
		elif _same_colour(cols[i], trousers) and torso:
			trousers_high = maxf(trousers_high, v.y)
	# The brows (hair-coloured) sit at 1.70 and the eyes at 1.665; the cap must start above both.
	assert_float(hair_front_low).is_greater(1.69)
	assert_float(shirt_low).is_greater(0.93)
	assert_float(trousers_high).is_greater(1.0)


## add-character-features 1.1: body A is today's body exactly; body B is reshaped and joined.
func test_an_old_profile_builds_the_same_body_and_body_b_differs() -> void:
	var old := {"skin": 2, "top": 1, "height": 1.0, "build": 1.0}  # saved before bodies existed
	var with_a := old.merged({"body": 0})
	var m_old := CharacterMesh.build(old)
	var m_a := CharacterMesh.build(with_a)
	assert_int(m_old.surface_get_array_len(0)).is_equal(m_a.surface_get_array_len(0))
	assert_bool(m_old.get_aabb().is_equal_approx(m_a.get_aabb())).is_true()
	var m_b := CharacterMesh.build(old.merged({"body": 1}))
	assert_int(m_b.surface_get_array_len(0)).is_equal(m_a.surface_get_array_len(0))  # same parts
	# Shoulders: the arms hang closer in. Hips: the legs stand wider apart.
	var arm := CharacterMesh.bone_index("upper_arm_l")
	var thigh := CharacterMesh.bone_index("thigh_l")
	assert_float(CharacterMesh.bone_pivot(arm, old.merged({"body": 1})).x).is_less(CharacterMesh.bone_pivot(arm, old).x)
	assert_float(CharacterMesh.bone_pivot(thigh, old.merged({"body": 1})).x).is_greater(CharacterMesh.bone_pivot(thigh, old).x)
	# Skinned and posed builds agree for body B (the skeleton follows the reshaped parts).
	var posed := CharacterMesh.build(old.merged({"body": 1}), {})
	assert_bool(posed.get_aabb().is_equal_approx(m_b.get_aabb())).is_true()


func test_body_labels_follow_the_tone() -> void:
	var before := ContentMode.current
	ContentMode.set_mode("clean", false)
	assert_str(CharacterProfile.label({"body": 0}, "body")).is_equal("A")
	assert_str(CharacterProfile.label({"body": 1}, "body")).is_equal("B")
	ContentMode.set_mode("gritty", false)
	assert_str(CharacterProfile.label({"body": 0}, "body")).is_equal("Man")
	assert_str(CharacterProfile.label({"body": 1}, "body")).is_equal("Woman")
	assert_str(ContentMode.text("body.label")).is_equal("Body")
	ContentMode.set_mode(before, false)


func test_random_profiles_split_between_the_bodies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var b := 0
	for i in range(400):
		b += int(CharacterProfile.random(rng)["body"])
	assert_int(b).is_between(140, 260)  # about half, from population.v0.json
