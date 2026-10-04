extends GdUnitTestSuite
## CharacterRagdoll on its own (no pedestrians): falls, flops, settles, holds, releases;
## impulses land on the bone nearest the hit. Plus the pedestrian pool built on it.


func _floor() -> void:
	var floor: StaticBody3D = auto_free(StaticBody3D.new())
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	cs.shape = box
	cs.position.y = -0.5
	floor.add_child(cs)
	add_child(floor)


func _ragdoll() -> CharacterRagdoll:
	_floor()
	var rd: CharacterRagdoll = auto_free(CharacterRagdoll.new())
	add_child(rd)
	return rd


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _bone(rd: CharacterRagdoll, name: String) -> PhysicalBone3D:
	return rd.bones[CharacterMesh.bone_index(name)]


func test_released_ragdoll_is_hidden_and_out_of_the_world() -> void:
	var rd := _ragdoll()
	assert_bool(rd.active).is_false()
	assert_bool(rd.visible).is_false()
	assert_int(rd.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	assert_int(rd.bones.size()).is_equal(CharacterMesh.BONES.size())
	assert_float(rd.total_mass()).is_equal_approx(75.0, 0.01)


func test_limbs_move_relative_to_the_torso_during_a_fall() -> void:
	var rd := _ragdoll()
	await _frames(1)
	rd.begin({}, Transform3D.IDENTITY, 0.0, 0.0)
	var spine := _bone(rd, "spine")
	var arm := _bone(rd, "upper_arm_l")
	var shin := _bone(rd, "shin_r")
	var arm_at_start := spine.global_transform.affine_inverse() * arm.global_position
	var shin_at_start := spine.global_transform.affine_inverse() * shin.global_position
	rd.apply_impulse(Vector3(0, 100, -900), Vector3(0, 0.5, 0), 0.7)
	await _frames(40)
	var arm_moved := (spine.global_transform.affine_inverse() * arm.global_position).distance_to(arm_at_start)
	var shin_moved := (spine.global_transform.affine_inverse() * shin.global_position).distance_to(shin_at_start)
	assert_float(maxf(arm_moved, shin_moved)).is_greater(0.1)  # not one rigid body


func test_impulse_lands_on_the_bone_nearest_the_hit() -> void:
	var rd := _ragdoll()
	await _frames(1)
	rd.begin({}, Transform3D.IDENTITY)
	assert_str(rd.nearest_bone(Vector3(0, 1.65, 0)).name).is_equal("head")
	assert_str(rd.nearest_bone(Vector3(0.11, 0.3, -0.1)).name).is_equal("shin_l")
	rd.apply_impulse(Vector3(0, 0, -30), Vector3(0, 1.65, -0.2))  # spread 0: a shot to the head
	await _frames(1)
	assert_float(_bone(rd, "head").linear_velocity.length()).is_greater(_bone(rd, "shin_l").linear_velocity.length())


func test_knee_and_head_hits_move_different_bones_first() -> void:
	var rd := _ragdoll()
	await _frames(1)
	rd.begin({}, Transform3D.IDENTITY)
	rd.apply_impulse(Vector3(0, 0, -40), Vector3(0.11, 0.4, -0.1))
	await _frames(1)
	assert_float(_bone(rd, "shin_l").linear_velocity.length()).is_greater(_bone(rd, "head").linear_velocity.length())


func test_body_settles_holds_its_pose_and_releases() -> void:
	var rd := _ragdoll()
	await _frames(1)
	rd.begin({}, Transform3D(Basis(), Vector3(0, 0.05, 0)))
	rd.apply_impulse(Vector3(0, 100, -600), Vector3(0, 0.5, 0), 0.7)
	await _frames(240)  # 4 s, the hit window
	assert_float(rd.velocity().length()).is_less(0.5)
	for pb in rd.bones:
		assert_float(pb.global_position.y).is_between(-0.1, 0.6)  # lying on the floor, not in it
	rd.settle()
	assert_bool(rd.is_settled()).is_true()
	var head_before := rd.rig.skeleton.get_bone_global_pose(CharacterMesh.bone_index("head")).origin
	await _frames(30)
	var head_after := rd.rig.skeleton.get_bone_global_pose(CharacterMesh.bone_index("head")).origin
	assert_vector(head_after).is_equal_approx(head_before, Vector3.ONE * 0.01)  # holds the fallen pose
	assert_float(head_before.y).is_less(0.6)  # and it is a lying pose, not the standing one
	rd.release()
	assert_bool(rd.visible).is_false()
	assert_bool(rd.active).is_false()


# --- the pedestrian pool ---

func _manager() -> PedestrianManager:
	_floor()
	var w := RoadGraph.PedestrianWay.new()
	w.id = "p1"
	w.kind = "sidewalk"
	w.width_m = 2.0
	w.road_class = "footway"
	w.polyline = PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0)])
	var ways: Array[RoadGraph.PedestrianWay] = [w]
	var m: PedestrianManager = auto_free(PedestrianManager.new())
	add_child(m)
	m.setup(WalkGraph.build(ways))
	m.enabled = false
	m.anchors = PackedVector3Array([Vector3(20, 0, 0)])
	return m


func _walker(m: PedestrianManager, distance: float) -> Pedestrian:
	var a := Pedestrian.new()
	a.path_id = 0
	a.distance = distance
	a.speed = 0.0
	a.transform = Transform3D(Basis(), m.walk.paths[0].position_at(distance))
	m.agents.append(a)
	return a


func test_knocked_down_pedestrian_falls_as_a_ragdoll_and_is_returned() -> void:
	var m := _manager()
	var a := _walker(m, 20.0)
	m._assign_bodies()
	await _frames(1)
	m.knock_down(a, Vector3(0, 100, -900), a.position() + Vector3.UP * 0.5)
	assert_object(a.ragdoll).is_not_null()
	assert_object(a.body).is_null()  # the walking body goes back to the pool
	assert_bool(a.ragdoll.active).is_true()
	var rd := a.ragdoll
	for i in range(int(float(m.config["hit_physics_s"]) * 60) + 5):
		m.step(1.0 / 60.0)
		await get_tree().physics_frame
	assert_int(a.state).is_equal(Pedestrian.State.DOWN)
	assert_bool(rd.is_settled()).is_true()
	assert_float(a.position().z).is_less(-2.0)  # the agent follows the body
	a.timer = 0.0
	m.step(1.0 / 60.0)
	assert_int(m.agents.size()).is_equal(0)
	assert_bool(rd.active).is_false()


func test_busy_pool_recycles_the_downed_body_with_least_time_left() -> void:
	var m := _manager()
	var pool := int(m.config["ragdoll_pool"])
	var downed: Array[Pedestrian] = []
	await _frames(1)
	for i in range(pool):
		var a := _walker(m, 10.0 + i * 3.0)
		m.knock_down(a, Vector3(0, 0, -100), a.position())
		a.state = Pedestrian.State.DOWN
		a.timer = 10.0 + i
		downed.append(a)
	var oldest_ragdoll := downed[0].ragdoll
	var newest := _walker(m, 60.0)
	m.knock_down(newest, Vector3(0, 0, -100), newest.position())
	assert_object(newest.ragdoll).is_same(oldest_ragdoll)  # least time left: its ragdoll reused
	assert_bool(m.agents.has(downed[0])).is_false()  # and that person is gone
	for i in range(1, downed.size()):
		assert_bool(m.agents.has(downed[i])).is_true()
