extends GdUnitTestSuite
## add-vehicle-and-building-damage 1.1-1.4: car health from crashes and hits, the stages and
## what they do, dents on a copy of the mesh, wrecks by tone (a clean stall mended by a reset;
## a burning wreck that explodes and chains), and getting in and out of a wreck.

const CAR := preload("res://actors/vehicles/placeholder_car.tscn")
const CarScript := preload("res://actors/vehicles/placeholder_car.gd")

var _mode_before: String
var _config_before: Dictionary


func before_test() -> void:
	_mode_before = ContentMode.current
	_config_before = VehicleDamage.config().duplicate()


func after_test() -> void:
	ContentMode.set_mode(_mode_before, false)
	VehicleDamage._config = _config_before


## A world with a wide floor at y 0.
func _world() -> Node3D:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	floor.add_child(shape)
	holder.add_child(floor)
	floor.position = Vector3(0, -0.5, 0)
	return holder


func _car(holder: Node3D, at: Vector3) -> VehicleBody3D:
	var car: VehicleBody3D = CAR.instantiate()
	holder.add_child(car)
	car.global_position = at
	return car


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


# --- the maths ------------------------------------------------------------------------

func test_a_gentle_bump_does_nothing_and_a_hard_crash_costs_more_the_faster_it_is() -> void:
	assert_float(VehicleDamage.crash_damage(4.0)).is_equal(0.0)
	var at_60 := VehicleDamage.crash_damage(60.0 / 3.6)
	assert_float(at_60).is_between(25.0, 40.0)
	assert_float(VehicleDamage.crash_damage(100.0 / 3.6)).is_greater(at_60)


func test_stages_by_health() -> void:
	assert_int(VehicleDamage.stage_for(100.0)).is_equal(VehicleDamage.Stage.FINE)
	assert_int(VehicleDamage.stage_for(70.0)).is_equal(VehicleDamage.Stage.SCUFFED)
	assert_int(VehicleDamage.stage_for(40.0)).is_equal(VehicleDamage.Stage.DENTED)
	assert_int(VehicleDamage.stage_for(10.0)).is_equal(VehicleDamage.Stage.SMOKING)
	assert_int(VehicleDamage.stage_for(0.0)).is_equal(VehicleDamage.Stage.WRECKED)


func test_the_outcome_follows_the_tone() -> void:
	ContentMode.set_mode("clean", false)
	assert_str(VehicleDamage.outcome()).is_equal("conk_out")
	ContentMode.set_mode("gritty", false)
	assert_str(VehicleDamage.outcome()).is_equal("burn")
	ContentMode.set_mode("dystopia", false)
	assert_str(VehicleDamage.outcome()).is_equal("spark")


func test_hits_dent_where_they_land_and_a_front_hit_once_dented_puts_the_lights_out() -> void:
	var d: VehicleDamage = auto_free(VehicleDamage.new())
	d.take(3.0, Vector3(0.9, 0.6, 0.0))
	assert_array(d.dents).is_empty()  # too light to dent
	d.take(30.0, Vector3(0.0, 0.6, -2.3))
	assert_int(d.dents.size()).is_equal(1)
	assert_bool(d.lights_out.has("front")).is_false()  # only scuffed so far
	d.take(30.0, Vector3(0.0, 0.6, -2.3))
	assert_int(d.stage).is_equal(VehicleDamage.Stage.DENTED)
	assert_bool(d.lights_out.has("front")).is_true()
	assert_bool(d.lights_out.has("rear")).is_false()
	d.mend()
	assert_float(d.health).is_equal(VehicleDamage.MAX_HEALTH)
	assert_array(d.dents).is_empty()
	assert_bool(d.lights_out.is_empty()).is_true()


func test_smoking_halves_the_power_and_a_wreck_has_none() -> void:
	var d: VehicleDamage = auto_free(VehicleDamage.new())
	assert_float(d.power_factor()).is_equal(1.0)
	d.take(80.0, Vector3.ZERO)
	assert_float(d.power_factor()).is_equal(VehicleDamage.tun("smoking_power"))
	d.take(80.0, Vector3.ZERO)
	assert_bool(d.is_wrecked()).is_true()
	assert_float(d.power_factor()).is_equal(0.0)


func test_a_dent_pushes_the_side_in_on_a_copy_and_leaves_the_shared_mesh_alone() -> void:
	var side := VehicleMesh.dent_point(Vector3(0.9, 0.6, 0.0), [{"at": Vector3(0.9, 0.6, 0.0), "depth": 0.2}], 0.9)
	assert_float(side.x).is_equal_approx(0.7, 0.001)
	var far := VehicleMesh.dent_point(Vector3(-0.9, 0.6, 0.0), [{"at": Vector3(0.9, 0.6, 0.0), "depth": 0.2}], 0.9)
	assert_float(far.x).is_equal_approx(-0.9, 0.0001)
	var front := VehicleMesh.dent_point(Vector3(0.0, 0.6, -2.3), [{"at": Vector3(0.0, 0.6, -2.3), "depth": 0.2}], 0.9)
	assert_float(front.z).is_equal_approx(-2.1, 0.001)
	var mesh := VehicleMesh.build(VehicleCatalogue.entry(VehicleCatalogue.default_player), VehicleMesh.Lod.LOD0, false)
	var before: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var copy := VehicleMesh.dented(mesh, [{"at": Vector3(0.9, 0.6, 0.0), "depth": 0.2}], 0.9)
	assert_int(copy.get_surface_count()).is_equal(mesh.get_surface_count())
	assert_object(copy.surface_get_material(2)).is_same(mesh.surface_get_material(2))
	assert_bool(copy.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == before).is_false()
	assert_bool(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == before).is_true()


func test_where_a_hit_lands_on_the_body() -> void:
	var front := CarScript.hit_point(Vector3(0, 0, -1), 1.8, 4.6, 1.5)
	assert_vector(front).is_equal_approx(Vector3(0, 0.675, -2.3), Vector3.ONE * 0.001)
	var side := CarScript.hit_point(Vector3(1, 0, 0.2), 1.8, 4.6, 1.5)
	assert_float(side.x).is_equal_approx(0.9, 0.001)


# --- on a car -------------------------------------------------------------------------

func test_a_car_driven_into_a_wall_is_damaged_and_dented() -> void:
	var world := _world()
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 4, 1)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.position = Vector3(0, 2, -12)
	var car := _car(world, Vector3(0, 0.3, 0))
	await _frames(10)
	car.linear_velocity = Vector3(0, 0, -20.0)
	await _frames(60)
	var d: VehicleDamage = car.damage
	assert_float(d.health).is_less(90.0)
	assert_array(d.dents).is_not_empty()
	assert_float((d.dents[0]["at"] as Vector3).z).is_less(0.0)  # the front took it
	assert_object((car.get_node("Mesh") as MeshInstance3D).mesh).is_not_same(car._base_mesh)


func test_the_body_slopes_up_at_nose_and_tail_to_the_small_bump_height() -> void:
	var hull := CarScript.body_shape(1.8, 1.5, 4.6, 0.2, 0.3)
	var nose_low := INF
	for p in hull.points:
		if is_equal_approx(p.z, -2.3):
			nose_low = minf(nose_low, p.y)
	assert_float(nose_low).is_equal_approx(0.35, 0.001)  # the nose clears a 30 cm edge
	var aabb := AABB(hull.points[0], Vector3.ZERO)
	for p in hull.points:
		aabb = aabb.expand(p)
	assert_vector(aabb.size).is_equal_approx(Vector3(1.8, 1.2, 4.6), Vector3.ONE * 0.001)


func test_a_curb_under_the_small_bump_height_does_no_damage_and_the_car_rides_over() -> void:
	var world := _world()
	var curb := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, 10)
	shape.shape = box
	curb.add_child(shape)
	world.add_child(curb)
	curb.position = Vector3(0, 0.1, -12)  # a 20 cm step up onto a 10 m wide kerb
	var car := _car(world, Vector3(0, 0.3, 0))
	await _frames(10)
	car.linear_velocity = Vector3(0, 0, -20.0)
	await _frames(45)
	assert_float(car.damage.health).is_equal(VehicleDamage.MAX_HEALTH)
	assert_float(car.global_position.z).is_less(-9.0)  # it got onto the step, not stopped at it


func test_a_wreck_stops_pulling() -> void:
	var world := _world()
	var car := _car(world, Vector3(0, 0.3, 0))
	await _frames(5)
	car.damage.take(200.0, Vector3.ZERO)
	car.override_throttle = 1.0
	await _frames(1)
	assert_float(car.engine_force).is_equal(0.0)


func test_in_clean_a_wreck_stalls_can_be_got_into_and_a_reset_mends_it() -> void:
	ContentMode.set_mode("clean", false)
	var world := _world()
	var car := _car(world, Vector3(0, 0.3, 0))
	await _frames(5)
	car.damage.take(200.0, Vector3(0.9, 0.6, 0))
	assert_str(car.damage.wreck_outcome).is_equal("conk_out")
	assert_bool(car.can_enter()).is_true()
	car._recover()
	assert_float(car.damage.health).is_equal(VehicleDamage.MAX_HEALTH)
	assert_array(car.damage.dents).is_empty()


func test_reset_keeps_damage_short_of_a_wreck() -> void:
	var world := _world()
	var car := _car(world, Vector3(0, 0.3, 0))
	await _frames(5)
	car.damage.take(60.0, Vector3(0.9, 0.6, 0))
	car._recover()
	assert_float(car.damage.health).is_equal(40.0)


func test_in_gritty_a_wreck_burns_explodes_and_takes_the_damaged_car_beside_it() -> void:
	ContentMode.set_mode("gritty", false)
	VehicleDamage.config()["burn_after_s"] = 0.05
	VehicleDamage.config()["explode_after_s"] = 0.05
	var world := _world()
	var car := _car(world, Vector3(0, 0.3, 0))
	var next := _car(world, Vector3(4, 0.3, 0))
	var far := _car(world, Vector3(60, 0.3, 0))
	await _frames(5)
	next.damage.take(70.0, Vector3(0.9, 0.6, 0))  # badly damaged already
	var blasts := []
	car.damage.exploded.connect(func(at: Vector3, _r: float) -> void: blasts.append(at))
	car.damage.take(200.0, Vector3.ZERO)
	assert_bool(car.can_enter()).is_false()
	assert_int(car.damage.fire).is_equal(VehicleDamage.Fire.SMOULDER)
	await _frames(30)
	assert_int(blasts.size()).is_equal(1)
	assert_int(car.damage.fire).is_equal(VehicleDamage.Fire.SHELL)
	assert_bool(next.damage.is_wrecked()).is_true()  # the chain
	assert_float(far.damage.health).is_equal(VehicleDamage.MAX_HEALTH)
	# A reset leaves a burning wreck where it is.
	var where := car.global_position
	car._recover()
	assert_bool(car.damage.is_wrecked()).is_true()
	assert_vector(car.global_position).is_equal_approx(where, Vector3.ONE * 0.5)
