extends GdUnitTestSuite
## Backlog 2026-10-06 (human: "ideally a shadow would be wicked too"): a soft blob under the
## police helicopter by day, on the ground straight below, fading with height and gone at night.


func _helicopter() -> PoliceHelicopter:
	var h: PoliceHelicopter = auto_free(PoliceHelicopter.new())
	h.config = {}
	add_child(h)
	h.set_physics_process(false)  # placed by hand; no flying
	return h


func test_the_blob_fades_with_height_and_is_gone_at_night() -> void:
	var h := _helicopter()
	var full := h.tun("shadow_alpha")
	assert_float(h.shadow_alpha_at(10.0, 0.0)).is_equal_approx(full, 0.001)
	var mid := h.shadow_alpha_at(80.0, 0.0)
	assert_float(mid).is_between(0.01, full - 0.01)
	assert_float(h.shadow_alpha_at(h.tun("shadow_fade_to_m") + 1.0, 0.0)).is_equal(0.0)
	assert_float(h.shadow_alpha_at(10.0, h.tun("shadow_night_off"))).is_equal(0.0)
	assert_float(h.shadow_alpha_at(10.0, 1.0)).is_equal(0.0)
	assert_float(h.shadow_alpha_at(10.0, h.tun("shadow_night_off") * 0.5)).is_equal_approx(full * 0.5, 0.001)
	assert_float(h.shadow_size_at(60.0)).is_greater(h.shadow_size_at(0.0))


func test_the_blob_lies_on_the_ground_straight_below() -> void:
	var floor: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor.add_child(shape)
	add_child(floor)
	floor.global_position = Vector3(0, 4.5, 0)  # top at y 5
	var h := _helicopter()
	h.global_position = Vector3(3, 60, -2)
	await get_tree().physics_frame
	h.night = 0.0
	h.update_shadow()
	var blob: MeshInstance3D = h.get_node("Shadow")
	assert_bool(blob.visible).is_true()
	assert_float(blob.global_position.y).is_equal_approx(5.06, 0.02)
	assert_float(Vector2(blob.global_position.x - 3.0, blob.global_position.z + 2.0).length()).is_less(0.01)
	h.night = 1.0
	h.update_shadow()
	assert_bool(blob.visible).is_false()
