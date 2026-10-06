extends GdUnitTestSuite
## add-weapons-and-combat 2.6: the weapon in the hand, the arm's poses, the swing and the kick.


func _rig() -> CharacterRig:
	var rig: CharacterRig = auto_free(CharacterRig.new())
	rig.profile = CharacterProfile.random()
	add_child(rig)
	return rig


func test_every_weapon_variant_has_a_model() -> void:
	for path in ["res://actors/combat/weapons.v0.json", "res://actors/police/officer_weapon.json"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var defs: Array = data["weapons"] if data.has("weapons") else [data]
		for d: Dictionary in defs:
			for mode: String in d["variants"]:
				var id := str(d["variants"][mode].get("model", ""))
				assert_str(id).override_failure_message("%s %s has no model" % [d["id"], mode]).is_not_empty()
				var built := HeldWeapon.build_model(id)
				var root: Node3D = built["root"]
				assert_int(root.get_child_count()).override_failure_message("model %s is empty" % id).is_greater(1)
				var gun := str(d.get("mechanic", "")) != "melee"
				assert_bool(built["muzzle"] != null).override_failure_message("%s muzzle" % id).is_equal(gun)
				assert_bool(built["tip"] != null).override_failure_message("%s tip" % id).is_equal(not gun)
				root.free()


func test_the_model_sits_in_the_hand_and_goes_with_empty_hands() -> void:
	var held: HeldWeapon = auto_free(HeldWeapon.new())
	held.rig = _rig()
	add_child(held)
	held.set_weapon({"model": "pistol"})
	assert_bool(held.has_weapon()).is_true()
	await get_tree().process_frame
	var hand := held.rig.skeleton.get_bone_global_pose(held.rig.skeleton.find_bone(HeldWeapon.FORE))
	assert_float(held.muzzle().distance_to(held.rig.skeleton.global_transform * hand.origin)).is_less(0.8)
	held.set_weapon({})
	assert_bool(held.has_weapon()).is_false()
	assert_bool(held.muzzle() == Vector3.INF).is_true()


func test_aiming_raises_the_arm_straight_ahead() -> void:
	var held_pose := HeldWeapon.arm_pose(false, -1.0, -1.0)
	var aim_pose := HeldWeapon.arm_pose(true, -1.0, -1.0)
	var down := Vector3.DOWN
	# The upper arm hangs near the side when held, and points ahead (-Z) when aiming.
	assert_float((held_pose[HeldWeapon.UPPER] * down).y).is_less(-0.9)
	assert_float((aim_pose[HeldWeapon.UPPER] * down).z).is_less(-0.99)


func test_a_swing_cuts_from_the_right_across_to_the_left() -> void:
	var start: Quaternion = HeldWeapon.arm_pose(false, 0.05, -1.0)[HeldWeapon.UPPER]
	var finish: Quaternion = HeldWeapon.arm_pose(false, 0.95, -1.0)[HeldWeapon.UPPER]
	# +X is the body's right while facing -Z.
	assert_float((start * Vector3.DOWN).x).is_greater(0.3)
	assert_float((finish * Vector3.DOWN).x).is_less(-0.3)


func test_a_shot_kicks_the_muzzle_up_then_settles() -> void:
	var still: Quaternion = HeldWeapon.arm_pose(true, -1.0, -1.0)[HeldWeapon.FORE]
	var kicked: Quaternion = HeldWeapon.arm_pose(true, -1.0, 0.0)[HeldWeapon.FORE]
	var settled: Quaternion = HeldWeapon.arm_pose(true, -1.0, 1.0)[HeldWeapon.FORE]
	assert_float(still.angle_to(kicked)).is_greater(0.2)
	assert_float(still.angle_to(settled)).is_less(0.01)


func test_a_swing_leaves_a_trail_then_ends() -> void:
	var held: HeldWeapon = auto_free(HeldWeapon.new())
	held.rig = _rig()
	add_child(held)
	held.set_weapon({"model": "sabre"})
	held.swing()
	assert_bool(held.swinging()).is_true()
	for i in range(6):
		await get_tree().process_frame
	assert_int(held._trail_pts.size()).is_greater(1)
	await get_tree().create_timer(HeldWeapon.SWING_S + HeldWeapon.TRAIL_LIFE_S + 0.1).timeout
	assert_bool(held.swinging()).is_false()
	assert_int(held._trail_pts.size()).is_equal(0)
