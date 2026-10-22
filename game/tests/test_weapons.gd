extends GdUnitTestSuite
## add-weapons-and-combat 2.x: tone variants, cycling, rate and reload, the hit path in every
## tone, and the mark pool.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")

var _mode_before: String


func before_test() -> void:
	_mode_before = ContentMode.current


func after_test() -> void:
	ContentMode.set_mode(_mode_before, false)


func _use_mode(mode: String) -> void:
	assert_bool(ContentMode.set_mode(mode, false)).is_true()


func test_each_tone_puts_its_own_weapons_in_hand() -> void:
	var expect := {"clean": ["Paint brush", "Paintball gun"], "gritty": ["Knife", "Pistol"], "dystopia": ["Sabre", "Blaster"]}
	for mode: String in expect:
		_use_mode(mode)
		var ws := WeaponSet.new()
		ws.slot = 1
		assert_str(str(ws.current().get("name"))).override_failure_message(mode).is_equal(expect[mode][0])
		ws.slot = 2
		assert_str(str(ws.current().get("name"))).is_equal(expect[mode][1])
	_use_mode("clean")
	var clean := WeaponSet.new()
	clean.slot = 2
	assert_str(str(clean.current()["mechanic"])).is_equal("projectile")
	assert_bool(bool(clean.current()["lethal"])).is_false()


func test_a_lethal_variant_is_refused_without_lethal_weapons() -> void:
	_use_mode("clean")
	var def := {"id": "x", "slot": 3, "mechanic": "hitscan", "variants": {"fallback": {"name": "Gun", "impact": "bullet", "lethal": true}, "clean": {"name": "Sneaky", "impact": "bullet", "lethal": true}}}
	assert_dict(WeaponSet.resolve(def)).is_empty()


func test_cycling_goes_hands_melee_gun_hands() -> void:
	var ws := WeaponSet.new()
	assert_int(ws.slot).is_equal(0)
	ws.cycle()
	assert_int(ws.slot).is_equal(1)
	ws.cycle()
	assert_int(ws.slot).is_equal(2)
	ws.cycle()
	assert_int(ws.slot).is_equal(0)


func _shooter() -> Shooter:
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(p)
	var s: Shooter = auto_free(Shooter.new())
	s.player = p
	add_child(s)
	return s


func test_rate_magazine_and_reload() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.weapons.slot = 2
	assert_bool(s.pull_trigger()).is_true()
	assert_bool(s.pull_trigger()).is_false()  # still cycling
	assert_int(s.weapons.rounds()).is_equal(11)
	s.weapons.ammo["gun"] = 0
	s._cooldown = 0.0
	assert_bool(s.pull_trigger()).is_false()  # empty: starts a reload
	assert_float(s._reload_left).is_greater(0.0)
	for i in range(int(1.6 * 60)):
		await get_tree().physics_frame
	assert_int(s.weapons.rounds()).is_equal(12)


func _walker(m: PedestrianManager) -> Array:
	var a := Pedestrian.new()
	a.path_id = 0
	a.distance = 10.0
	a.speed = 1.3
	a.transform = Transform3D(Basis(), m.walk.paths[0].position_at(10.0))
	m.agents.append(a)
	var body: PedestrianBody = auto_free(PedestrianManager.BODY_SCENE.instantiate())
	add_child(body)
	body.agent = a
	return [a, body]


func _manager() -> PedestrianManager:
	var w := RoadGraph.PedestrianWay.new()
	w.id = "p1"
	w.kind = "sidewalk"
	w.width_m = 2.0
	w.road_class = "footway"
	w.polyline = PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0)])
	var m: PedestrianManager = auto_free(PedestrianManager.new())
	add_child(m)
	m.setup(WalkGraph.build([w] as Array[RoadGraph.PedestrianWay]))
	m.enabled = false
	return m


func test_a_hit_knocks_down_in_gritty_and_paints_in_clean() -> void:
	var s := _shooter()
	s.peds = _manager()
	_use_mode("gritty")
	var pair := _walker(s.peds)
	s.weapons.slot = 2
	s.hit(s.weapons.current(), pair[1], Vector3(10, 1, 0), Vector3.LEFT, Vector3(0, 1, 0))
	assert_int((pair[0] as Pedestrian).state).is_equal(Pedestrian.State.HIT)
	_use_mode("clean")
	var pair2 := _walker(s.peds)
	s.weapons.slot = 2
	s.hit(s.weapons.current(), pair2[1], Vector3(10, 1, 0), Vector3.LEFT, Vector3(0, 1, 0))
	var a: Pedestrian = pair2[0]
	assert_int(a.state).is_equal(Pedestrian.State.WALKING)  # nobody goes down in clean
	assert_int(a.paint_index).is_greater(0)
	assert_float(a.fleeing).is_greater(0.0)
	var x0 := a.position().x
	for i in range(60):
		s.peds.step(1.0 / 60.0)
	assert_float(absf(a.position().x - x0)).is_greater(2.5)  # running, faster than a walk


func test_the_mark_pool_recycles_oldest_first() -> void:
	var fx: CombatEffects = auto_free(CombatEffects.new())
	add_child(fx)
	fx.cap = 3
	for i in range(5):
		fx.mark("hole", Vector3(i, 1, 0), Vector3.BACK)
	assert_int(fx.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D).size()).is_equal(3)
	assert_int(fx.marks_shown()).is_equal(3)
	fx.clear_marks()
	assert_int(fx.marks_shown()).is_equal(0)


func test_a_shot_damages_a_car_and_paint_does_not() -> void:
	# add-vehicle-and-building-damage: hits on a car take its impact kind's vehicle_damage.
	var s := _shooter()
	var car: VehicleBody3D = auto_free(load("res://actors/vehicles/placeholder_car.tscn").instantiate())
	add_child(car)
	car.global_position = Vector3(10, 0, 0)
	_use_mode("gritty")
	s.weapons.slot = 2
	s.hit(s.weapons.current(), car, Vector3(9.1, 0.8, 0), Vector3.LEFT, Vector3(0, 1, 0))
	assert_float(car.damage.health).is_less(VehicleDamage.MAX_HEALTH)
	_use_mode("clean")
	car.damage.mend()
	s.weapons.slot = 2
	s.hit(s.weapons.current(), car, Vector3(9.1, 0.8, 0), Vector3.LEFT, Vector3(0, 1, 0))
	assert_float(car.damage.health).is_equal(VehicleDamage.MAX_HEALTH)
