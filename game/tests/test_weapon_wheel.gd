extends GdUnitTestSuite
## add-weapon-selector: icon lookup and fallbacks, picking and stepping in every tone, tap
## against hold on LB / Tab, the wheel's direction maths, cancel, pages, the tone rebuild, the
## idle tile's flash, and that choosing never touches time or the camera.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const ICON_DIR := "res://ui/hud/icons/weapons"
const NAMES := {
	"clean": ["Fists", "Paint brush", "Paintball gun"],
	"gritty": ["Fists", "Knife", "Pistol"],
	"dystopia": ["Fists", "Sabre", "Blaster"],
}

var _mode_before: String


## A page of something else, standing in for a later kind (throwables).
class FakePage extends WheelPage:
	var chosen: int = -1

	func title() -> String:
		return "Throwables"

	func entries() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for n in ["Rock", "Can", "Bottle", "Brick"]:
			out.append({"icon": WeaponIcons.texture(PackedStringArray(["missing"])), "name": n, "sub": "", "enabled": true})
		return out

	func current_index() -> int:
		return chosen

	func choose(index: int) -> void:
		chosen = index


func before_test() -> void:
	_mode_before = ContentMode.current


func after_test() -> void:
	ContentMode.set_mode(_mode_before, false)
	for a in ["weapon_next", "fire", "reload"]:
		Input.action_release(a)


func _use_mode(mode: String) -> void:
	assert_bool(ContentMode.set_mode(mode, false)).is_true()


func _wheel() -> WeaponWheel:
	var w: WeaponWheel = auto_free(WeaponWheel.new())
	add_child(w)
	return w


## A shooter on a player, with a wheel and an idle tile.
func _shooter() -> Shooter:
	var p: Player = auto_free(PLAYER_SCENE.instantiate())
	add_child(p)
	var s: Shooter = auto_free(Shooter.new())
	s.player = p
	s.wheel = _wheel()
	s.tile = auto_free(WeaponTile.new())
	add_child(s.tile)
	add_child(s)
	return s


func _names(entries: Array[Dictionary]) -> Array:
	var out := []
	for e in entries:
		out.append(str(e["name"]))
	return out


func _press(action: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


# --- 1.1 icons ---


func test_icon_names_go_icon_then_model_then_mechanic_then_missing() -> void:
	var w := {"icon": "star", "model": "knife", "mechanic": "melee"}
	assert_array(Array(WeaponSet.icon_names_for(w))).is_equal(["star", "knife", "generic_melee", "missing"])
	assert_array(Array(WeaponSet.icon_names_for({"mechanic": "projectile"}))).is_equal(["generic_projectile", "missing"])
	assert_array(Array(WeaponSet.icon_names_for({}))).is_equal(["missing"])


func test_a_weapon_without_its_own_icon_uses_its_model_then_its_mechanic() -> void:
	assert_str(WeaponIcons.resolve(WeaponSet.icon_names_for({"model": "knife", "mechanic": "melee"}))).is_equal("knife")
	# A model with no icon (the officers' net gun) and a pack PNG that isn't there both fall through.
	assert_str(WeaponIcons.resolve(WeaponSet.icon_names_for({"model": "net_gun", "mechanic": "projectile"}))).is_equal("generic_projectile")
	assert_str(WeaponIcons.resolve(WeaponSet.icon_names_for({"icon": "user://no/such/icon.png", "mechanic": "hitscan"}))).is_equal("generic_hitscan")
	assert_str(WeaponIcons.resolve(PackedStringArray(["nothing_here"]))).is_equal("missing")
	assert_object(WeaponIcons.texture(PackedStringArray(["nothing_here"]))).is_not_null()


func test_every_held_model_and_the_fists_have_their_own_icon() -> void:
	var models: Array = ["fists"]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WeaponSet.WEAPONS_PATH))
	for w: Dictionary in data["weapons"]:
		for v: Dictionary in w["variants"].values():
			if v.has("model") and not models.has(v["model"]):
				models.append(v["model"])
	assert_int(models.size()).is_equal(7)
	for m in models + ["generic_melee", "generic_hitscan", "generic_projectile", "missing"]:
		assert_bool(ResourceLoader.exists(ICON_DIR.path_join(str(m) + ".svg"))).override_failure_message("no icon for %s" % m).is_true()
		assert_str(WeaponIcons.resolve(PackedStringArray([str(m)]))).is_equal(str(m))


func test_a_pack_png_icon_is_used_when_it_exists() -> void:
	var path := "user://test_wheel_icon.png"
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	img.save_png(path)
	assert_str(WeaponIcons.resolve(WeaponSet.icon_names_for({"icon": path, "model": "knife"}))).is_equal(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- 1.2 picking and stepping ---


func test_every_tone_fills_three_slots_in_order() -> void:
	for mode: String in NAMES:
		_use_mode(mode)
		var ws := WeaponSet.new()
		assert_array(ws.available()).is_equal([0, 1, 2])
		var page := WeaponPage.new(ws)
		assert_array(_names(page.entries())).is_equal(NAMES[mode])


func test_pick_refuses_a_slot_the_tone_leaves_empty() -> void:
	var path := "user://test_wheel_weapons.json"
	var data := {"schema_version": 0, "weapons": [
		{"id": "a", "slot": 1, "mechanic": "melee", "rate_s": 0.4, "magazine": 0, "reload_s": 0.0, "range_m": 1.5, "spread_deg": 0.0,
			"variants": {"fallback": {"name": "Bat", "impact": "blade", "lethal": true}}},
		{"id": "b", "slot": 2, "mechanic": "hitscan", "rate_s": 0.3, "magazine": 6, "reload_s": 1.0, "range_m": 40.0, "spread_deg": 0.0,
			"variants": {"fallback": {"name": "Pea shooter", "impact": "paint", "lethal": false}}},
	]}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	_use_mode("clean")  # lethal weapons off: the bat is refused
	var ws := WeaponSet.new(path)
	assert_array(ws.available()).is_equal([0, 2])
	assert_bool(ws.pick(1)).is_false()
	assert_int(ws.slot).is_equal(0)
	assert_bool(ws.pick(2)).is_true()
	# The page has two segments and the bat has none; the pea shooter shows the generic gun.
	var page := WeaponPage.new(ws)
	assert_array(_names(page.entries())).is_equal(["Fists", "Pea shooter"])
	assert_str(WeaponIcons.resolve(ws.icon_names(2))).is_equal("generic_hitscan")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_number_keys_pick_by_position_in_every_tone() -> void:
	for mode: String in NAMES:
		_use_mode(mode)
		var s := _shooter()
		assert_bool(s.pick_position(2)).is_true()
		assert_str(str(s.weapons.current()["name"])).is_equal(NAMES[mode][2])
		assert_bool(s.pick_position(0)).is_true()
		assert_int(s.weapons.slot).is_equal(0)
		assert_bool(s.pick_position(5)).is_false()
	for n in range(1, 10):
		assert_bool(InputMap.has_action("weapon_slot_%d" % n)).is_true()
	assert_str(Controls.binding_text("weapon_slot_1", false)).is_equal("1")
	assert_str(Controls.binding_text("wheel_page", true)).is_equal("RB")


func test_a_tap_steps_and_does_not_open_the_wheel() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.step_next(0.0, true)
	s.step_next(0.05, true)
	s.step_next(0.05, false)
	assert_int(s.weapons.slot).is_equal(1)
	assert_bool(s.wheel.is_open()).is_false()


func test_a_hold_opens_the_wheel_and_the_release_takes_the_pointed_slot() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.step_next(0.0, true)
	for i in range(4):
		s.step_next(0.06, true)
	assert_bool(s.wheel.is_open()).is_true()
	assert_int(s.weapons.slot).is_equal(0)  # opening changes nothing
	s.wheel.steer(Vector2.from_angle(WeaponWheel.segment_angle(2, 3)))
	assert_int(s.wheel.selected).is_equal(2)
	s.step_next(0.02, false)
	assert_bool(s.wheel.is_open()).is_false()
	assert_str(str(s.weapons.current()["name"])).is_equal("Pistol")


func test_releasing_with_nothing_pointed_keeps_the_slot() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.weapons.slot = 1
	s.step_next(0.0, true)
	s.step_next(0.3, true)
	s.wheel.steer(Vector2(0.9, 0.0))
	s.wheel.steer(Vector2.ZERO)  # the stick back in the middle lets go
	assert_int(s.wheel.selected).is_equal(-1)
	s.step_next(0.02, false)
	assert_int(s.weapons.slot).is_equal(1)


# --- 1.3 the wheel ---


func test_direction_maths_first_at_the_top_then_clockwise() -> void:
	assert_int(WeaponWheel.segment_for(Vector2.UP, 3)).is_equal(0)
	assert_int(WeaponWheel.segment_for(Vector2.RIGHT, 4)).is_equal(1)
	assert_int(WeaponWheel.segment_for(Vector2.DOWN, 4)).is_equal(2)
	assert_int(WeaponWheel.segment_for(Vector2.LEFT, 4)).is_equal(3)
	assert_int(WeaponWheel.segment_for(Vector2.ZERO, 4)).is_equal(-1)
	assert_int(WeaponWheel.segment_for(Vector2.UP, 0)).is_equal(-1)
	for n in [1, 3, 5, 8]:
		for i in range(n):
			var dir := Vector2.from_angle(WeaponWheel.segment_angle(i, n))
			assert_int(WeaponWheel.segment_for(dir, n)).is_equal(i)
			# Anywhere within half a segment of it still picks it.
			assert_int(WeaponWheel.segment_for(dir.rotated(PI / float(n) * 0.9), n)).is_equal(i)


func test_past_max_segments_the_rest_go_on_an_outer_ring() -> void:
	assert_bool(WeaponWheel.ring_counts(3, 8) == Vector2i(3, 0)).is_true()
	assert_bool(WeaponWheel.ring_counts(11, 8) == Vector2i(8, 3)).is_true()
	assert_int(WeaponWheel.pick(Vector2.UP, false, 11, 8)).is_equal(0)
	assert_int(WeaponWheel.pick(Vector2.UP, true, 11, 8)).is_equal(8)
	assert_int(WeaponWheel.pick(Vector2.from_angle(WeaponWheel.segment_angle(2, 3)), true, 11, 8)).is_equal(10)
	assert_int(WeaponWheel.pick(Vector2.UP, true, 3, 8)).is_equal(0)  # no outer ring: the inner one


func test_mouse_points_once_it_has_moved_far_enough() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.wheel.open_wheel()
	var px := float(WeaponWheel.tunables()["mouse_px"]) * s.wheel.hud_scale()
	s.wheel.move_mouse(Vector2(0, -px * 0.25))
	assert_int(s.wheel.selected).is_equal(-1)
	s.wheel.move_mouse(Vector2(0, -px))
	assert_int(s.wheel.selected).is_equal(0)
	s.wheel.move_mouse(Vector2(px * 10.0, px * 1.25))
	assert_int(s.wheel.selected).is_equal(1)


func test_b_or_esc_closes_without_a_change() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.wheel.open_wheel()
	s.wheel.select(2)
	s.wheel._input(_press("ui_cancel"))
	assert_bool(s.wheel.is_open()).is_false()
	assert_int(s.weapons.slot).is_equal(0)
	assert_bool(s.wheel.just_closed()).is_true()
	# Still holding LB after the cancel: the release does not step either.
	s.step_next(0.0, true)
	s.step_next(0.3, true)
	s.wheel.close(false)
	s.step_next(0.02, false)
	assert_int(s.weapons.slot).is_equal(0)


func test_segments_follow_the_tone_and_rebuild_on_a_change() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.wheel.open_wheel()
	assert_array(_names(s.wheel.entries())).is_equal(NAMES["gritty"])
	_use_mode("clean")
	assert_array(_names(s.wheel.entries())).is_equal(NAMES["clean"])
	_use_mode("dystopia")
	assert_array(_names(s.wheel.entries())).is_equal(NAMES["dystopia"])
	assert_object(s.wheel.entries()[1]["icon"]).is_same(WeaponIcons.texture(PackedStringArray(["sabre"])))


func test_rounds_show_under_a_gun() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.weapons.slot = 2
	s.weapons.use_round()
	var e: Dictionary = s.page.entries()[2]
	assert_str(str(e["sub"])).is_equal("11 / 12")
	assert_str(str(s.page.entries()[1]["sub"])).is_equal("")


func test_one_page_hides_paging_and_a_second_page_steps() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.wheel.open_wheel()
	s.wheel._input(_press("wheel_page"))
	assert_int(s.wheel.page).is_equal(0)  # a single page: nothing to step to
	var fake := FakePage.new()
	s.wheel.pages.append(fake)
	s.wheel._input(_press("wheel_page"))
	assert_int(s.wheel.page).is_equal(1)
	assert_array(_names(s.wheel.entries())).is_equal(["Rock", "Can", "Bottle", "Brick"])
	s.wheel.steer(Vector2.RIGHT)
	assert_bool(s.wheel.close(true)).is_true()
	assert_int(fake.chosen).is_equal(1)
	assert_int(s.weapons.slot).is_equal(0)  # the weapons page is untouched
	s.wheel.open_wheel()
	s.wheel.step_page(1)
	assert_int(s.wheel.page).is_equal(0)
	s.wheel.close(false)


func test_choosing_never_touches_time_and_holds_the_camera_and_the_trigger() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.weapons.slot = 2
	s._sync_slot()
	s.wheel.open_wheel()
	Input.action_press("fire")
	s._physics_process(1.0 / 60.0)
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_bool(get_tree().paused).is_false()
	assert_bool(s.player.look_locked).is_true()
	assert_int(s.weapons.rounds()).is_equal(12)  # fire did nothing
	s.wheel.close(false)
	s._physics_process(1.0 / 60.0)  # just closed: the press that closed it does nothing else
	assert_int(s.weapons.rounds()).is_equal(12)
	assert_bool(s.player.look_locked).is_false()
	Input.action_release("fire")


func test_driving_closes_the_wheel() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.wheel.open_wheel()
	s.player.stuck_s = 1.0  # any inactive state closes it
	s._physics_process(1.0 / 60.0)
	assert_bool(s.wheel.is_open()).is_false()
	assert_bool(s.player.look_locked).is_false()


func test_each_tone_has_its_own_accent() -> void:
	var seen := []
	for mode: String in NAMES:
		_use_mode(mode)
		var c := ContentMode.hud_accent()
		assert_bool(c.is_equal_approx(Color.WHITE)).is_false()
		assert_bool(seen.has(c.to_html())).is_false()
		seen.append(c.to_html())


# --- 1.4 the idle tile ---


func test_the_tile_shows_the_slot_and_flashes_on_a_tap_step() -> void:
	_use_mode("gritty")
	var s := _shooter()
	assert_object(s.tile.icon).is_same(WeaponIcons.texture(PackedStringArray(["fists"])))
	assert_bool(s.tile.flashing()).is_false()
	s.step_next(0.0, true)
	s.step_next(0.05, false)
	assert_object(s.tile.icon).is_same(WeaponIcons.texture(PackedStringArray(["knife"])))
	assert_bool(s.tile.flashing()).is_true()
	s.tile._process(1.0)
	assert_bool(s.tile.flashing()).is_false()


func test_the_tile_follows_a_tone_change_without_flashing() -> void:
	_use_mode("gritty")
	var s := _shooter()
	s.weapons.slot = 1
	s._sync_slot()
	s.tile._process(1.0)
	_use_mode("clean")
	assert_object(s.tile.icon).is_same(WeaponIcons.texture(PackedStringArray(["brush"])))
	assert_bool(s.tile.flashing()).is_false()
