extends GdUnitTestSuite
## Co-op pieces that need no network: pack checks, snapshot round trips, remote interpolation.


func test_manifest_mismatch_names_the_field() -> void:
	var host := {"id": "a", "version": "1", "hash": "x"}
	assert_str(Session.mismatch_reason(host, {"id": "a", "version": "1", "hash": "x"})).is_empty()
	assert_str(Session.mismatch_reason(host, {"id": "b", "version": "1", "hash": "x"})).contains("pack id differs")
	assert_str(Session.mismatch_reason(host, {"id": "a", "version": "2", "hash": "x"})).contains("version")
	assert_str(Session.mismatch_reason(host, {"id": "a", "version": "1", "hash": "y"})).contains("hash")


func test_traffic_snapshot_round_trips_positions_headings_and_colours() -> void:
	var m: TrafficManager = auto_free(TrafficManager.new())
	add_child(m)
	var colors: Array = m.config["colors"]
	var a := TrafficAgent.new()
	a.transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), Vector3(10, 2, 30))
	var c: Array = colors[3]
	a.color = Color(float(c[0]), float(c[1]), float(c[2]))
	var far := TrafficAgent.new()
	far.transform = Transform3D(Basis(), Vector3(900, 0, 0))
	m.agents = [a, far]
	var data := m.snapshot(Vector3.ZERO, 350.0)
	assert_int(data.size()).is_equal(6)
	var mirror: TrafficManager = auto_free(TrafficManager.new())
	add_child(mirror)
	mirror.mirror = true
	mirror.apply_snapshot(data)
	assert_int(mirror.agents.size()).is_equal(1)
	var b: TrafficAgent = mirror.agents[0]
	assert_float(b.position().distance_to(Vector3(10, 2, 30))).is_less(0.01)
	assert_float((-b.transform.basis.z).dot(Vector3(1, 0, 0))).is_greater(0.999)
	assert_object(b.color).is_equal(a.color)


func test_remote_player_interpolates_toward_the_newest_sample() -> void:
	var r: RemotePlayer = auto_free(RemotePlayer.new())
	add_child(r)
	r.set_process(false)  # the test drives the clock
	r.setup(2, Color.BLUE)
	r.push_state(false, Transform3D(Basis(), Vector3(0, 0, 0)), Transform3D.IDENTITY)
	r._clock = 0.05
	r.push_state(false, Transform3D(Basis(), Vector3(10, 0, 0)), Transform3D.IDENTITY)
	r._clock = 0.1
	r.push_state(true, Transform3D(Basis(), Vector3(20, 0, 0)), Transform3D(Basis(), Vector3(20, 0, 5)))
	r._process(0.04)  # clock 0.14, target 0.04: four fifths of the way from sample 1 to sample 2
	assert_float(r.global_position.x).is_equal_approx(8.0, 0.2)
	assert_bool(r.driving).is_false()
	r._process(0.1)  # clock 0.24, target 0.14: past the newest sample, clamps to it
	assert_float(r.global_position.x).is_equal_approx(20.0, 0.01)
	assert_bool(r.driving).is_true()
	assert_float(r.car_target.origin.z).is_equal_approx(5.0, 0.01)


func test_host_releases_and_retires_agents_near_a_point() -> void:
	var m: TrafficManager = auto_free(TrafficManager.new())
	add_child(m)
	var a := TrafficAgent.new()
	a.transform = Transform3D(Basis(), Vector3(50, 0, 0))
	a.color = Color.GREEN
	var b := TrafficAgent.new()
	b.transform = Transform3D(Basis(), Vector3(300, 0, 0))
	m.agents = [a, b]
	assert_dict(m.release_near(Vector3(400, 0, 0))).is_empty()  # nothing within reach
	var got := m.release_near(Vector3(52, 0, 0))
	assert_object(got["color"]).is_equal(Color.GREEN)
	assert_int(m.agents.size()).is_equal(1)
	assert_bool(m.hit_near(Vector3(301, 0, 0), Vector3(10, 0, 0))).is_true()
	assert_bool(b.retired).is_true()
	assert_bool(m.hit_near(Vector3(301, 0, 0), Vector3.ZERO)).is_false()  # already retired
