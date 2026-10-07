extends GdUnitTestSuite
## add-police-combat: the player's weapons reach officers, officers react by tone from the mode
## data (knocked down in gritty and dystopia, tagged out in clean), fists follow the unarmed
## rules, hitting and downing an officer raise the wanted level, a downed officer stops seeing
## the player, backup heads for the scene and a hit officer takes cover by their car.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")

var _mode_before: String


func before_test() -> void:
	_mode_before = ContentMode.current


func after_test() -> void:
	ContentMode.set_mode(_mode_before, false)


func _use_mode(mode: String) -> void:
	assert_bool(ContentMode.set_mode(mode, false)).is_true()


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
	w.config["police_per_star"] = [0, 0, 0, 0]  # only the officers and cars a test makes
	var pm: PoliceManager = auto_free(PoliceManager.new())
	pm.wanted = w
	pm.graph = _graph()
	pm.player = p
	pm.holder = holder
	add_child(pm)
	return pm


func _shooter(pm: PoliceManager) -> Shooter:
	var s: Shooter = auto_free(Shooter.new())
	s.player = pm.player
	s.police = pm
	add_child(s)
	return s


## The tone's gun (slot 2) as the player holds it.
func _gun() -> Dictionary:
	var ws := WeaponSet.new()
	ws.slot = 2
	return ws.current()


## Hits `o` with `w` until they are out of the fight or `limit` hits are spent; returns the
## results in order.
func _hit_until_out(pm: PoliceManager, o: Node3D, w: Dictionary, limit: int = 10) -> Array[String]:
	var out: Array[String] = []
	var from := pm.player.global_position + Vector3.UP
	for i in range(limit):
		var r := pm.hit_officer(o, w, o.global_position + Vector3.UP, from)
		out.append(r)
		if r != "stagger":
			break
	return out


# --- 1.1 reaching officers ---


func test_rays_find_an_officer_and_the_hit_reaches_the_police() -> void:
	_use_mode("gritty")
	var pm := _setup()
	var s := _shooter(pm)
	var o := pm.place_officer(Vector3(0, 0, -6))
	await get_tree().physics_frame
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 1.2, 0), Vector3(0, 1.2, -20))
	q.exclude = [pm.player.get_rid()]
	var res := pm.player.get_world_3d().direct_space_state.intersect_ray(q)
	assert_bool(res.is_empty()).is_false()
	assert_bool(res["collider"] is OfficerBody).is_true()
	assert_object((res["collider"] as OfficerBody).officer).is_same(o)
	s.hit(_gun(), res["collider"], res["position"], res["normal"], Vector3(0, 1, 0))
	assert_int(int(o.get_meta("hp", 100.0))).is_less(100)
	assert_float(float(o.get_meta("stagger_t", 0.0))).is_greater(0.0)


func test_the_melee_sweep_and_paintballs_reach_officers() -> void:
	_use_mode("gritty")
	var pm := _setup()
	var o := pm.place_officer(Vector3(0, 0, -1.0))
	await get_tree().physics_frame
	var shape := SphereShape3D.new()
	shape.radius = 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), Vector3(0, 1, -1.0))
	q.exclude = [pm.player.get_rid()]
	var found := false
	for r in pm.player.get_world_3d().direct_space_state.intersect_shape(q, 8):
		found = found or (r["collider"] is OfficerBody and (r["collider"] as OfficerBody).officer == o)
	assert_bool(found).override_failure_message("the melee sweep's shape query misses officers").is_true()
	var s := _shooter(pm)
	var ball := s._make_ball()
	assert_int(ball.collision_mask & OfficerBody.LAYER).is_not_equal(0)
	assert_int(ball.collision_mask & PedestrianBody.LAYER).is_not_equal(0)
	assert_int(ball.collision_mask & 1).is_not_equal(0)


func test_an_officer_out_of_the_fight_cannot_be_hit_again() -> void:
	_use_mode("gritty")
	var pm := _setup()
	var o := pm.place_officer(Vector3(0, 0, -6))
	_hit_until_out(pm, o, _gun())
	assert_bool(pm.in_fight(o)).is_false()
	assert_str(pm.hit_officer(o, _gun(), o.global_position, Vector3.ZERO)).is_equal("")
	var body: OfficerBody = o.get_meta("body")
	assert_int(body.collision_layer).is_equal(0)


# --- 1.2 reactions by tone ---


func test_gritty_the_pistol_staggers_then_knocks_down() -> void:
	_use_mode("gritty")
	var pm := _setup()
	var o := pm.place_officer(Vector3(0, 0, -6))
	var results := _hit_until_out(pm, o, _gun())
	assert_array(results).contains_exactly(["stagger", "stagger", "down"])
	assert_bool(pm.downed.has(o)).is_true()
	assert_bool(pm.officers.has(o)).is_false()
	var rd: CharacterRagdoll = o.get_meta("ragdoll", null)
	assert_object(rd).is_not_null()
	assert_bool(rd.active).is_true()
	assert_bool((o.get_meta("rig") as CharacterRig).visible).is_false()


func test_dystopia_the_blaster_knocks_down_in_two() -> void:
	_use_mode("dystopia")
	var pm := _setup()
	var o := pm.place_officer(Vector3(0, 0, -6))
	assert_array(_hit_until_out(pm, o, _gun())).contains_exactly(["stagger", "down"])


func test_clean_paint_tags_out_and_never_knocks_down() -> void:
	_use_mode("clean")
	var pm := _setup()
	var o := pm.place_officer(Vector3(0, 0, -6))
	var results := _hit_until_out(pm, o, _gun())
	assert_array(results).contains_exactly(["stagger", "stagger", "stagger", "tagged"])
	assert_bool(o.has_meta("ragdoll")).is_false()
	assert_str(str(o.get_meta("state"))).is_equal("tagged")
	var rig: CharacterRig = o.get_meta("rig")
	assert_float(rig.position.y).is_less(-0.5)  # sitting on the ground
	assert_float(rig.override_weight).is_equal(1.0)  # hands up
	assert_float(rig.leg_weight).is_equal(1.0)


func test_a_tagged_out_officer_walks_back_and_gets_in() -> void:
	_use_mode("clean")
	var pm := _setup()
	pm.wanted.set_stars(1)
	var car: VehicleBody3D = auto_free(PoliceManager.CAR_SCENE.instantiate())
	pm.holder.add_child(car)
	car.global_position = Vector3(4, 0.6, -6)
	car.set_meta("police", true)
	car.set_meta("officer_out", true)
	pm.cars.append(car)
	var o := pm.place_officer(Vector3(0, 0, -6))
	o.set_meta("car", car)
	_hit_until_out(pm, o, _gun())
	pm.wanted.config["officer_combat"] = {"tag_out_s": 0.2}
	o.set_meta("tag_t", 0.2)
	for i in range(int(4.0 * 60)):
		await get_tree().physics_frame
		if not is_instance_valid(o):
			break
	assert_bool(is_instance_valid(o)).override_failure_message("the tagged-out officer never got back in").is_false()
	assert_bool(pm.downed.is_empty()).is_true()
	# Back in the car, the chase goes on: a fresh officer may get out again at once.
	for other in pm.officers:
		assert_bool(other != o).is_true()


func test_the_mode_data_decides_and_no_violence_never_knocks_down() -> void:
	_use_mode("gritty")
	assert_str(PoliceManager.outcome()).is_equal("knock_down")
	_use_mode("dystopia")
	assert_str(PoliceManager.outcome()).is_equal("knock_down")
	_use_mode("clean")
	assert_str(PoliceManager.outcome()).is_equal("tag_out")


func test_fists_follow_the_unarmed_rules_in_every_tone() -> void:
	_use_mode("gritty")
	var pm := _setup()
	var o := pm.place_officer(Vector3(0, 0, -2))
	var from := Vector3(0, 1, 0)
	var punch := {"impact": "fist", "move": "punch", "lethal": false}
	var kick := {"impact": "fist", "move": "kick", "lethal": false}
	assert_str(pm.hit_officer(o, punch, o.global_position, from)).is_equal("stagger")
	assert_str(pm.hit_officer(o, punch, o.global_position, from)).is_equal("stagger")
	assert_str(pm.hit_officer(o, punch, o.global_position, from)).is_equal("down")  # the third of a streak
	var o2 := pm.place_officer(Vector3(2, 0, -2))
	assert_str(pm.hit_officer(o2, kick, o2.global_position, from)).is_equal("down")  # one kick
	_use_mode("clean")
	var o3 := pm.place_officer(Vector3(-2, 0, -2))
	for i in range(6):
		assert_str(pm.hit_officer(o3, kick if i % 2 == 0 else punch, o3.global_position, from)).is_equal("stagger")
	assert_bool(pm.in_fight(o3)).is_true()


func test_toughness_comes_back_after_a_pause() -> void:
	_use_mode("gritty")
	var pm := _setup()
	var o := pm.place_officer(Vector3(0, 0, -6))
	var from := Vector3(0, 1, 0)
	for i in range(5):
		assert_str(pm.hit_officer(o, _gun(), o.global_position, from)).is_equal("stagger")
		pm._clock += float(pm.combat("recover_s", 3.0)) + 0.5
	assert_bool(pm.in_fight(o)).is_true()


# --- 2.1 heat ---


func test_hitting_an_officer_adds_a_star_without_a_witness_and_downing_one_another() -> void:
	_use_mode("gritty")
	var pm := _setup()
	assert_int(pm.wanted.stars).is_equal(0)
	var o := pm.place_officer(Vector3(0, 0, -6))
	pm.hit_officer(o, _gun(), o.global_position, Vector3(0, 1, 0))
	assert_int(pm.wanted.stars).is_equal(1)
	pm.hit_officer(o, _gun(), o.global_position, Vector3(0, 1, 0))
	assert_int(pm.wanted.stars).is_equal(2)
	pm.hit_officer(o, _gun(), o.global_position, Vector3(0, 1, 0))  # down: assault and officer down
	assert_int(pm.wanted.stars).is_equal(3)


func test_a_downed_officer_stops_seeing_the_player() -> void:
	_use_mode("gritty")
	var pm := _setup()
	pm.wanted.set_stars(1)
	pm.wanted.target = pm.player
	var o := pm.place_officer(Vector3(0, 0, -10))
	for i in range(3):
		await get_tree().physics_frame
	assert_bool(pm.wanted.police_sees(pm.player.global_position)).is_true()
	_hit_until_out(pm, o, _gun())
	for i in range(3):
		await get_tree().physics_frame
	assert_bool(pm.wanted.police_sees(pm.player.global_position)).is_false()
	var kinds: Array = pm.markers().map(func(m: Dictionary) -> String: return m["kind"])
	assert_array(kinds).not_contains(["officer"])


# --- 2.2 backup and cover ---


func test_backup_drives_to_where_an_officer_went_down() -> void:
	_use_mode("gritty")
	var pm := _setup()
	var o := pm.place_officer(Vector3(200, 0, 0))
	var before := pm.cars.size()
	_hit_until_out(pm, o, _gun())
	var scene := o.global_position  # where they went down (the staggers pushed them a little)
	assert_int(pm.cars.size()).is_equal(before + 1)
	var car: VehicleBody3D = pm.cars[pm.cars.size() - 1]
	assert_bool(car.has_meta("backup_to")).is_true()
	assert_float((car.get_meta("backup_to") as Vector3).distance_to(scene)).is_less(0.01)
	var d := car.global_position.distance_to(scene)
	assert_float(d).is_between(85.0, 165.0)  # from the spawn ring around the scene


func test_backup_at_the_scene_lets_its_officer_out_at_once() -> void:
	_use_mode("gritty")
	var pm := _setup()
	pm.wanted.set_stars(1)
	var car: VehicleBody3D = auto_free(PoliceManager.CAR_SCENE.instantiate())
	pm.holder.add_child(car)
	car.global_position = Vector3(100, 0.6, 0)
	car.set_meta("police", true)
	car.set_meta("backup_to", Vector3(105, 0, 0))
	pm.cars.append(car)
	for i in range(30):
		await get_tree().physics_frame
		if not pm.officers.is_empty():
			break
	assert_int(pm.officers.size()).is_equal(1)
	assert_bool(car.has_meta("backup_to")).is_false()


func test_a_hit_officer_takes_cover_beside_their_car_away_from_the_player() -> void:
	_use_mode("gritty")
	var pm := _setup()
	pm.wanted.set_stars(1)
	var car: VehicleBody3D = auto_free(PoliceManager.CAR_SCENE.instantiate())
	pm.holder.add_child(car)
	car.global_position = Vector3(10, 0.6, 0)
	car.set_meta("police", true)
	car.set_meta("officer_out", true)
	pm.cars.append(car)
	var o := pm.place_officer(Vector3(6, 0, 0))
	o.set_meta("car", car)
	assert_str(pm.hit_officer(o, _gun(), o.global_position + Vector3.UP, Vector3(0, 1, 0))).is_equal("stagger")
	var cover := pm.cover_point(o)
	assert_bool(cover == Vector3.INF).is_false()
	assert_float(cover.x).is_greater(car.global_position.x)  # the far side of the car
	var x0 := o.global_position.x
	for i in range(int(1.5 * 60)):
		await get_tree().physics_frame
	assert_float(o.global_position.x).is_greater(x0 + 1.0)  # went to cover, not at the player
	pm._clock += float(pm.combat("cover_s", 3.0)) + 1.0
	assert_bool(pm.cover_point(o) == Vector3.INF).is_true()


func test_a_staggered_officer_neither_moves_nor_fires() -> void:
	_use_mode("gritty")
	var pm := _setup()
	pm.wanted.set_stars(3)  # pistols out at three stars
	var hits: Array[float] = []
	pm.shot_at.connect(func(d: float) -> void: hits.append(d))
	var o := pm.place_officer(Vector3(0, 0, -8))
	pm.hit_officer(o, _gun(), o.global_position, Vector3(0, 1, 0))
	o.set_meta("stagger_t", 1.0)
	var at := o.global_position
	for i in range(30):
		await get_tree().physics_frame
	assert_int(hits.size()).is_equal(0)
	assert_float(o.global_position.distance_to(at)).is_less(0.01)
