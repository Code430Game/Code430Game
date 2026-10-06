extends GdUnitTestSuite
## update-police-pursuit: who sees the player and how close they are to losing the police
## (Wanted), the seen badge, the minimap marker states, a helicopter that can be outrun or
## lost under dense canopy, and patrol cars that stay parked while their officer is out.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const DT := 1.0 / 60.0


## A straight road east from the origin, a node every 20 m to 400 m.
func _graph() -> RoadGraph:
	var nodes := {}
	var edges := []
	for i in range(21):
		nodes["n%d" % i] = {"id": "n%d" % i, "position": [i * 20.0, 0.0, 0.0], "ground_y": 0.0, "junction_type": "junction", "control": "none", "osm_node_ids": [i]}
	for i in range(20):
		edges.append({"id": "w%d" % i, "from": "n%d" % i, "to": "n%d" % (i + 1), "class": "residential", "polyline": [[i * 20.0, 0.0, 0.0], [(i + 1) * 20.0, 0.0, 0.0]], "length_m": 20.0, "lanes_forward": 1, "lanes_backward": 1, "oneway": false, "speed_kph": 40, "width_m": 7.0, "layer": 0, "bridge": false, "tunnel": false, "name": null, "osm_way_id": i, "control_from": "none", "control_to": "none"})
	return RoadGraph.from_dict({"nodes": nodes.values(), "edges": edges, "pedestrian_ways": [], "bus_stops": []})


func _setup() -> PoliceManager:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(800, 1, 800)
	shape.shape = box
	floor.add_child(shape)
	holder.add_child(floor)
	floor.position = Vector3(200, -0.5, 0)
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	holder.add_child(p)
	p.global_position = Vector3(0, 1, 0)
	var w: Wanted = auto_free(Wanted.new())
	add_child(w)
	var pm: PoliceManager = auto_free(PoliceManager.new())
	pm.wanted = w
	pm.graph = _graph()
	pm.player = p
	pm.holder = holder
	add_child(pm)
	return pm


## A wanted level with a target far from any police, in the tree so it ticks.
func _wanted(stars: int) -> Wanted:
	var w: Wanted = auto_free(Wanted.new())
	add_child(w)
	var t: Node3D = auto_free(Node3D.new())
	add_child(t)
	t.global_position = Vector3(500, 0, 500)
	w.target = t
	w.set_stars(stars)
	return w


func test_hidden_progress_runs_toward_each_levels_lose_time() -> void:
	for stars in [1, 2, 3]:
		var w := _wanted(stars)
		var lose := w.lose_s()
		assert_float(lose).is_equal(float((w.config["lose_s"] as Array)[stars]))
		w._process(lose * 0.5)
		assert_bool(w.seen()).is_false()
		assert_float(w.hidden_progress()).is_equal_approx(0.5, 0.001)
		assert_int(w.stars).is_equal(stars)


func test_being_seen_empties_the_progress_and_names_who_sees() -> void:
	var w := _wanted(2)
	w._process(4.0)
	assert_float(w.hidden_progress()).is_greater(0.0)
	w.police_positions = PackedVector3Array([w.target.global_position + Vector3(20, 0, 0)])
	w._process(DT)
	assert_bool(w.ground_sees).is_true()
	assert_bool(w.seen()).is_true()
	assert_float(w.hidden_progress()).is_equal(0.0)
	w.police_positions = PackedVector3Array()
	w.helicopter_sees = true
	w._process(DT)
	assert_bool(w.ground_sees).is_false()
	assert_bool(w.seen()).is_true()
	w.clear()
	w.helicopter_sees = false
	assert_bool(w.seen()).is_false()
	assert_float(w.hidden_progress()).is_equal(0.0)


func test_the_badge_shows_seen_hidden_and_nothing() -> void:
	var badge: SeenBadge = auto_free(SeenBadge.new())
	badge.show_wanted(0, true, true, 0.0)
	assert_int(badge.state).is_equal(SeenBadge.State.OFF)
	assert_bool(badge.visible).is_false()
	badge.show_wanted(3, true, false, 0.4)
	assert_int(badge.state).is_equal(SeenBadge.State.SEEN)
	assert_bool(badge.heli_sees).is_true()
	assert_bool(badge.ground_sees).is_false()
	assert_float(badge.progress).is_equal(0.0)  # seen: the ring is empty
	badge.show_wanted(2, false, true, 0.0)
	assert_bool(badge.ground_sees).is_true()
	badge.show_wanted(2, false, false, 0.6)
	assert_int(badge.state).is_equal(SeenBadge.State.HIDDEN)
	assert_bool(badge.visible).is_true()
	assert_float(badge.progress).is_equal_approx(0.6, 0.001)
	assert_bool(badge.heli_sees or badge.ground_sees).is_false()


func test_the_hidden_badge_blinks_and_a_sighting_restarts_it_bright() -> void:
	var badge: SeenBadge = auto_free(SeenBadge.new())
	var half := float(SeenBadge._tun().get("blink_s", 0.45))
	badge.show_wanted(1, false, false, 0.2)
	assert_bool(badge.blink_on()).is_true()
	badge._process(half + 0.01)
	assert_bool(badge.blink_on()).is_false()
	badge._process(half)
	assert_bool(badge.blink_on()).is_true()
	badge.show_wanted(1, false, true, 0.0)
	assert_bool(badge.blink_on()).is_true()  # seen is always bright


func test_minimap_markers_say_which_units_see_the_player() -> void:
	var pm := _setup()
	pm.wanted.config["police_per_star"] = [0, 0, 0, 0]
	var near: VehicleBody3D = auto_free(PoliceManager.CAR_SCENE.instantiate())
	var far: VehicleBody3D = auto_free(PoliceManager.CAR_SCENE.instantiate())
	pm.holder.add_child(near)
	pm.holder.add_child(far)
	near.global_position = Vector3(30, 0.6, 0)
	far.global_position = Vector3(120, 0.6, 0)
	pm.cars.append(near)
	pm.cars.append(far)
	var by_x := {}
	for m: Dictionary in pm.markers():
		by_x[int(round((m["at"] as Vector3).x))] = m
	assert_bool(by_x[30]["sees"]).is_true()
	assert_bool(by_x[120]["sees"]).is_false()
	var heli: PoliceHelicopter = auto_free(PoliceHelicopter.new())
	pm.holder.add_child(heli)
	pm.helicopter = heli
	heli.state = PoliceHelicopter.State.SEARCH
	var hm: Dictionary = pm.markers().filter(func(m: Dictionary) -> bool: return m["kind"] == "helicopter")[0]
	assert_bool(hm["searching"]).is_true()
	assert_bool(hm["sees"]).is_false()
	pm.helicopter = null


## Steps the helicopter by hand for `seconds`, moving the target `velocity` each step.
func _fly(heli: PoliceHelicopter, target: Node3D, velocity: Vector3, seconds: float) -> void:
	for i in range(int(seconds / DT)):
		target.global_position += velocity * DT
		heli._physics_process(DT)


func _chasing_helicopter(at: Vector3) -> Array:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var target: Node3D = auto_free(Node3D.new())
	holder.add_child(target)
	target.global_position = at
	var heli: PoliceHelicopter = auto_free(PoliceHelicopter.new())
	holder.add_child(heli)
	heli.set_physics_process(false)
	heli.target = target
	heli.state = PoliceHelicopter.State.CHASE
	heli.global_position = at + Vector3(38, 55, 0)
	return [heli, target]


func test_a_fast_car_in_the_open_outruns_the_helicopter() -> void:
	var pair := _chasing_helicopter(Vector3.ZERO)
	var heli: PoliceHelicopter = pair[0]
	# 50 m/s is 180 km/h: the fastest cars in the catalogue reach it, the helicopter can't. It
	# starts 38 m ahead and 55 m up, so at 35 m/s the gap passes its 150 m sight after about
	# 12 s and it gives up 2 s later; at the old 45 m/s it would still be on them at 16 s.
	_fly(heli, pair[1], Vector3(50, 0, 0), 16.0)
	assert_int(heli.state).override_failure_message("the helicopter kept up with a car at 180 km/h").is_equal(PoliceHelicopter.State.SEARCH)
	assert_bool(heli.sees_target()).is_false()


func test_standing_still_in_the_open_the_helicopter_keeps_the_player() -> void:
	var pair := _chasing_helicopter(Vector3.ZERO)
	var heli: PoliceHelicopter = pair[0]
	_fly(heli, pair[1], Vector3.ZERO, 10.0)
	assert_int(heli.state).is_equal(PoliceHelicopter.State.CHASE)
	assert_bool(heli.sees_target()).is_true()


func test_the_helicopter_reads_its_tunables_from_config() -> void:
	var heli: PoliceHelicopter = auto_free(PoliceHelicopter.new())
	assert_float(heli.tun("speed_mps")).is_equal(35.0)
	heli.config = {"speed_mps": 20.0}
	assert_float(heli.tun("speed_mps")).is_equal(20.0)
	assert_float(heli.tun("sight_m")).is_equal(float(PoliceHelicopter.DEFAULTS["sight_m"]))
	var cfg: Dictionary = (auto_free(Wanted.new()) as Wanted).config
	assert_float(float((cfg["helicopter"] as Dictionary)["speed_mps"])).is_equal(35.0)


## A tree row [x, y, z, archetype, height, crown, seed, source].
static func _tree(x: float, z: float, source: String = "scatter") -> Array:
	return [x, 0.0, z, "broadleaf", 10.0, 3.5, 1, source]


## A park clump: seven trees in a 10 m patch round (cx, cz).
static func _park(cx: float, cz: float) -> Array:
	var rows: Array = []
	for off: Vector2 in [Vector2.ZERO, Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4), Vector2(4, 4), Vector2(-4, -4)]:
		rows.append(_tree(cx + off.x, cz + off.y))
	return rows


func test_dense_canopy_blocks_the_view_from_above() -> void:
	var cover := CanopyCover.new(_park(0.0, 0.0))
	var under := Vector3(0, 1, 0)
	assert_bool(cover.blocks(under + Vector3(38, 55, 0), under)).is_true()
	assert_bool(cover.blocks(Vector3(38, 55, 0) + Vector3(60, 0, 0), Vector3(60, 1, 0))).is_false()  # open ground


func test_a_row_of_street_trees_is_not_cover() -> void:
	var rows: Array = []
	for i in range(8):
		rows.append(_tree(i * 10.0, 0.0, "row"))
	var cover := CanopyCover.new(rows)
	var under := Vector3(30, 1, 0)
	assert_bool(cover.blocks(under + Vector3(0, 55, 38), under)).is_false()


func test_the_helicopter_loses_a_player_under_dense_canopy() -> void:
	var pair := _chasing_helicopter(Vector3(0, 1, 0))
	var heli: PoliceHelicopter = pair[0]
	_fly(heli, pair[1], Vector3.ZERO, 0.5)
	assert_bool(heli.sees_target()).is_true()
	heli.canopy = CanopyCover.new(_park(0.0, 0.0))
	_fly(heli, pair[1], Vector3.ZERO, float(PoliceHelicopter.DEFAULTS["lost_s"]) + 0.5)
	assert_bool(heli.sees_target()).is_false()
	assert_int(heli.state).is_equal(PoliceHelicopter.State.SEARCH)


func test_a_patrol_car_stays_parked_while_its_officer_is_out_and_drives_once_they_are_back() -> void:
	var pm := _setup()
	pm.wanted.config["police_per_star"] = [0, 0, 0, 0]
	var car: VehicleBody3D = auto_free(PoliceManager.CAR_SCENE.instantiate())
	pm.holder.add_child(car)
	car.global_position = Vector3(0, 0.6, 0)
	pm.player.enter_vehicle(car)
	pm.wanted.set_stars(1)
	var cop: VehicleBody3D = auto_free(PoliceManager.CAR_SCENE.instantiate())
	pm.holder.add_child(cop)
	cop.global_position = Vector3(12, 0.6, 0)
	cop.set_meta("police", true)
	pm.cars.append(cop)
	await get_tree().create_timer(0.5).timeout
	assert_int(pm.officers.size()).is_equal(1)
	assert_bool(cop.has_meta("officer_out")).is_true()
	# The player drives off west: the empty car must not follow.
	var parked_at := cop.global_position
	for i in range(60):
		car.linear_velocity = Vector3(-12, 0, 0)
		await get_tree().physics_frame
		if cop.has_meta("officer_out"):
			assert_float(Vector2(cop.global_position.x - parked_at.x, cop.global_position.z - parked_at.z).length()).override_failure_message("an empty patrol car drove after the player").is_less(0.5)
	# The officer runs back and gets in; then the car can drive again.
	for i in range(240):
		if pm.officers.is_empty():
			break
		car.linear_velocity = Vector3(-12, 0, 0)
		await get_tree().physics_frame
	assert_bool(pm.officers.is_empty()).override_failure_message("the officer never got back in").is_true()
	assert_bool(cop.has_meta("officer_out")).is_false()
	pm.wanted.clear()
	await get_tree().physics_frame
