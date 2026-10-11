extends GdUnitTestSuite
## People from the art kit (adopt-art-kit stage 2, KitCharacter): the parts, their bones, the
## colours from the profile, the budget and the choices.

const MAX_PERSON_TRIANGLES := 3600


func after_test() -> void:
	KitCharacter.enabled = true


func test_both_bodies_are_built_with_every_choice() -> void:
	assert_bool(KitCharacter.active()).is_true()
	for body in [0, 1]:
		var k := KitCharacter.pack(body)
		assert_bool(k.is_empty()).is_false()
		assert_int(KitCharacter.choices(body, "hair").size()).is_equal(CharacterProfile.HAIR_NAMES.size())
		assert_int(KitCharacter.choices(body, "beard").size()).is_equal(CharacterProfile.BEARD_NAMES.size())
		assert_int(KitCharacter.choices(body, "hat").size()).is_equal(CharacterProfile.HAT_NAMES.size())
		assert_int(KitCharacter.choices(body, "outfit").size()).is_equal(KitCharacter.count("outfit"))
		var parts := KitCharacter._model(body)
		for key in ["hair_parts", "beard_parts", "hat_parts", "hat_under"]:
			for name: String in k[key]:
				if name != "":
					assert_bool(parts.has(name)).override_failure_message("%d %s" % [body, name]).is_true()
		for o in range(KitCharacter.count("outfit")):
			for slot in ["Top", "Legs", "Feet"]:
				assert_bool(parts.has("Outfit%d_%s" % [o, slot])).is_true()


func test_bones_sit_where_their_parts_are() -> void:
	for body in [0, 1]:
		var piv := func(b: String) -> Vector3: return KitCharacter.pivot(body, b)
		assert_float(piv.call("upper_arm_l").x).is_greater(0.05)
		assert_float(piv.call("upper_arm_l").x).is_equal_approx(-piv.call("upper_arm_r").x, 0.001)
		assert_float(piv.call("head").y).is_greater(piv.call("spine").y)
		assert_float(piv.call("shin_l").y).is_less(piv.call("thigh_l").y)
		assert_float(piv.call("forearm_l").y).is_less(piv.call("upper_arm_l").y)
		var parts := KitCharacter._model(body)
		for name: String in parts:
			for surface: Array in parts[name]:
				var verts: PackedVector3Array = surface[2]
				var bones: PackedInt32Array = surface[4]
				for i in range(verts.size()):
					var bone: String = CharacterMesh.BONES[bones[i]][0]
					var v := verts[i]
					var where := "%d %s %s %s" % [body, name, bone, v]
					if bone.ends_with("_l"):
						assert_float(v.x).override_failure_message(where).is_greater(-0.02)
					elif bone.ends_with("_r"):
						assert_float(v.x).override_failure_message(where).is_less(0.02)
					if bone == "head":
						assert_float(v.y).override_failure_message(where).is_greater(piv.call("head").y - 0.12)
					elif bone.begins_with("shin"):
						assert_float(v.y).override_failure_message(where).is_less(piv.call("shin_l").y + 0.08)


func test_feet_on_the_ground_and_height_from_the_profile() -> void:
	var man := CharacterMesh.build({"body": 0, "hair": 0, "hat": 0, "height": 1.0, "build": 1.0})
	assert_float(man.get_aabb().position.y).is_equal_approx(0.0, 0.01)
	# Bald: the top of the head is the man's height.
	assert_float(man.get_aabb().end.y).is_equal_approx(CharacterMesh.BASE_HEIGHT_M, 0.02)
	var tall := CharacterMesh.build({"body": 0, "hair": 0, "hat": 0, "height": 1.1, "build": 1.0})
	assert_float(tall.get_aabb().end.y).is_equal_approx(CharacterMesh.BASE_HEIGHT_M * 1.1, 0.02)
	var woman := CharacterMesh.build({"body": 1, "hair": 0, "hat": 0, "height": 1.0, "build": 1.0})
	assert_float(woman.get_aabb().end.y).is_less(man.get_aabb().end.y + 0.06)
	assert_float(woman.get_aabb().position.y).is_equal_approx(0.0, 0.01)


func test_every_look_stays_in_the_triangle_budget() -> void:
	for body in [0, 1]:
		for o in range(KitCharacter.count("outfit")):
			for hair in range(CharacterProfile.HAIR_NAMES.size()):
				for hat in range(CharacterProfile.HAT_NAMES.size()):
					var p := {"body": body, "outfit": o, "hair": hair, "hat": hat, "beard": 2, "glasses": 1}
					assert_int(KitCharacter.triangles(p)).is_less_equal(MAX_PERSON_TRIANGLES)


func test_the_profile_paints_the_roles_and_the_kit_keeps_its_colours() -> void:
	var p := CharacterProfile.normalise({"body": 0, "outfit": KitCharacter.index_of(0, "outfit", "suit"), "top": 2, "bottom": 5, "shoes": 2, "skin": 4, "hair": 1, "hair_colour": 3})
	var cols: PackedColorArray = CharacterMesh.build(p).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var seen := {}
	for c in cols:
		seen[c.to_rgba32()] = true
	for c: Color in [CharacterProfile.CLOTH[2], CharacterProfile.CLOTH[5], CharacterProfile.SHOE_COLOURS[2], CharacterProfile.SKIN[4], CharacterProfile.HAIR_COLOUR[3], CharacterMesh.EYE_COLOR]:
		assert_bool(_has(cols, c)).override_failure_message(str(c)).is_true()
	# The suit's shirt keeps the kit's white: more than the profile's colours are there.
	assert_int(seen.size()).is_greater(6)
	var other := CharacterMesh.build(p.merged({"top": 3}, true)).surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	assert_bool(_has(other, CharacterProfile.CLOTH[3])).is_true()
	assert_bool(_has(other, CharacterProfile.CLOTH[2])).is_false()


func test_hats_replace_the_hair_and_glasses_sit_in_front_of_the_eyes() -> void:
	var p := {"body": 0, "hair": 1, "hat": 1}
	var names := KitCharacter.part_names(p)
	assert_bool(names.has("Hair1")).is_false()
	assert_bool(names.has("Hat1")).is_true()
	var plain := CharacterMesh.build({"body": 1, "glasses": 0, "height": 1.0, "build": 1.0})
	var specs := CharacterMesh.build({"body": 1, "glasses": 1, "height": 1.0, "build": 1.0})
	assert_int(specs.surface_get_array_len(0)).is_greater(plain.surface_get_array_len(0))
	var eyes: Array = KitCharacter.pack(1)["eyes"]["centre"]
	var verts: PackedVector3Array = specs.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = specs.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var front := 0.0
	for i in range(verts.size()):
		if _near(cols[i], CharacterMesh.FRAME_COLOR) and verts[i].y > 1.4:  # dark shoes are lower down
			front = minf(front, verts[i].z)
			assert_float(verts[i].y).is_equal_approx(float(eyes[1]), 0.05)
	assert_float(front).is_less(float(eyes[2]))


func test_choices_are_named_by_the_kit_and_roles_find_their_outfits() -> void:
	assert_str(CharacterProfile.label({"body": 0, "hair": 4}, "hair")).is_equal("mohawk")
	assert_str(CharacterProfile.label({"body": 1, "hair": 1}, "hair")).is_equal("bob")
	assert_str(CharacterProfile.label({"body": 1, "outfit": 1}, "outfit")).is_equal("dress")
	for body in [0, 1]:
		for name in ["uniform", "worker", "punk", "suit"]:
			var i := KitCharacter.index_of(body, "outfit", name)
			assert_str(KitCharacter.choices(body, "outfit")[i]).is_equal(name)
	# Random people never draw a role's uniform.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(200):
		var p := CharacterProfile.random(rng)
		assert_str(CharacterProfile.label(p, "outfit")).is_not_equal("uniform")


func test_without_the_kit_the_primitive_body_is_drawn() -> void:
	var kit := CharacterMesh.build({"body": 0})
	KitCharacter.enabled = false
	var primitive := CharacterMesh.build({"body": 0})
	assert_int(primitive.surface_get_array_len(0)).is_not_equal(kit.surface_get_array_len(0))
	assert_float(CharacterMesh.bone_pivot(CharacterMesh.bone_index("upper_arm_l"), {"build": 1.0}).x).is_equal_approx(0.30, 0.001)


## Vertex colours come back at 8 bits a channel.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _has(cols: PackedColorArray, c: Color) -> bool:
	for x in cols:
		if _near(x, c):
			return true
	return false
