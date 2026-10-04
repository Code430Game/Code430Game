extends GdUnitTestSuite
## The crowd's walk cycle: pedestrian_walk.gdshader against CharacterMesh.walk_pose, phase
## from distance, standing still while waiting, one MultiMesh per body look.

const SHADER_PATH := "res://world/pedestrians/pedestrian_walk.gdshader"


func _manager() -> PedestrianManager:
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
	m.anchors = PackedVector3Array([Vector3.ZERO])
	return m


func _walker(m: PedestrianManager, distance: float, speed: float = 1.3) -> Pedestrian:
	var a := Pedestrian.new()
	a.path_id = 0
	a.distance = distance
	a.speed = speed
	a.transform = Transform3D(Basis(), m.walk.paths[0].position_at(distance))
	m.agents.append(a)
	return a


func test_shader_uses_the_same_walk_coefficients_as_the_player() -> void:
	var code := FileAccess.get_file_as_string(SHADER_PATH)
	for pair: Array in [["WALK_SWING", CharacterMesh.WALK_SWING], ["WALK_KNEE", CharacterMesh.WALK_KNEE],
			["WALK_ARM", CharacterMesh.WALK_ARM], ["WALK_ELBOW", CharacterMesh.WALK_ELBOW], ["WALK_BOB", CharacterMesh.WALK_BOB]]:
		var re := RegEx.create_from_string("const float %s = ([0-9.]+);" % pair[0])
		var found := re.search(code)
		assert_object(found).is_not_null()
		assert_float(float(found.get_string(1))).is_equal_approx(float(pair[1]), 0.0001)
	# Bone parents in the shader follow CharacterMesh.BONES.
	var parents := RegEx.create_from_string("PARENT\\[11\\] = int\\[\\]\\(([-0-9, ]+)\\)").search(code).get_string(1).split(",")
	for b in range(CharacterMesh.BONES.size()):
		assert_int(int(parents[b])).is_equal(CharacterMesh.bone_index(CharacterMesh.BONES[b][1]))


func test_chain_walk_matches_the_skeleton_pose() -> void:
	var profile := CharacterProfile.random(RandomNumberGenerator.new())
	var v := Vector3(0.05, 0.3, 0.02)
	for phase: float in [0.0, 0.9, PI * 0.5, 2.6, 4.4]:
		var pose := CharacterMesh.walk_pose(phase, 0.8)
		for b in range(CharacterMesh.BONES.size()):
			var expected := CharacterMesh.bone_global(b, profile, pose) * (v - CharacterMesh.bone_pivot(b, profile))
			var got := CharacterMesh.walk_vertex(v, b, profile, phase, 0.8)
			assert_vector(got).is_equal_approx(expected, Vector3.ONE * 0.0001)


func test_pool_meshes_carry_a_bone_per_vertex_in_the_rest_pose() -> void:
	var m := _manager()
	assert_int(m._pools.size()).is_equal(PedestrianManager.POOLS)
	for mmi in m._pools:
		var mm := mmi.multimesh
		assert_bool(mm.use_custom_data).is_true()
		var arrays := mm.mesh.surface_get_arrays(0)
		var bones: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		assert_int(bones.size()).is_equal(verts.size())
		assert_float(bones[0]).is_between(0.0, float(CharacterMesh.BONES.size() - 1))
		assert_object(mm.mesh.surface_get_material(0)).is_instanceof(ShaderMaterial)


func test_stride_phase_follows_distance_walked() -> void:
	var m := _manager()
	var a := _walker(m, 10.0, 1.3)
	for i in range(30):  # 0.5 s at 1.3 m/s: half a 1.3 m stride
		m.step(1.0 / 60.0)
	assert_float(a.walk_phase).is_equal_approx(PI, 0.1)
	assert_float(a.walk_amount).is_greater(0.9)


func test_walk_settles_to_standing_while_waiting() -> void:
	var m := _manager()
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	player.global_position = Vector3(13.0, 0.0, 0.0)
	m.obstacles = [player]
	var a := _walker(m, 8.0, 1.3)
	a.lateral = 0.0
	for i in range(60 * 4):  # about 2.3 s to reach the player, then waits (gives up after 4 s)
		m.step(1.0 / 60.0)
	assert_float(a.wait_time).is_greater(0.5)
	assert_float(a.walk_amount).is_less(0.02)


func test_render_writes_phase_and_amount_per_instance() -> void:
	var m := _manager()
	var a := _walker(m, 10.0)
	a.walk_phase = 1.25
	a.walk_amount = 0.6
	m._render()
	assert_int(m._pools[a.pool].multimesh.visible_instance_count).is_equal(1)
	# The headless renderer drops instance custom data, so check what _render writes.
	assert_that(PedestrianManager.walk_custom(a)).is_equal(Color(1.25, 0.6, 0.0, 0.0))
	a.state = Pedestrian.State.DOWN
	assert_float(PedestrianManager.walk_custom(a).g).is_equal(0.0)
