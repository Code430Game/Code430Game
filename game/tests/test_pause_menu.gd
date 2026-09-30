extends GdUnitTestSuite
## The pause menu must close on A (accept) and B (cancel) from a gamepad while the tree is paused.

const PAUSE_SCENE := preload("res://ui/pause/pause_menu.tscn")


func after_test() -> void:
	get_tree().paused = false


func _joy(button: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)


func test_a_resumes_and_b_resumes() -> void:
	var menu: PauseMenu = auto_free(PAUSE_SCENE.instantiate())
	add_child(menu)
	menu.open()
	await get_tree().process_frame
	assert_bool(get_tree().paused).is_true()
	_joy(JOY_BUTTON_A, true)
	await get_tree().process_frame
	_joy(JOY_BUTTON_A, false)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(menu.visible).override_failure_message("A did not resume").is_false()
	assert_bool(get_tree().paused).is_false()
	menu.open()
	await get_tree().process_frame
	_joy(JOY_BUTTON_B, true)
	await get_tree().process_frame
	_joy(JOY_BUTTON_B, false)
	await get_tree().process_frame
	assert_bool(menu.visible).override_failure_message("B did not resume").is_false()
