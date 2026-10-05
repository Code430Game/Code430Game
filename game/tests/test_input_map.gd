extends GdUnitTestSuite
## Every game action must be reachable with a gamepad alone (AGENTS.md, controller-first).

const REQUIRED_ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right",
	"look_up", "look_down", "look_left", "look_right",
	"sprint", "jump", "interact", "accelerate", "brake", "handbrake", "pause",
	"debug_modifier", "debug_toggle", "debug_graph", "reset_vehicle", "map_toggle", "radio_cycle",
	"horn", "look_behind", "camera_cycle", "headlights_cycle", "aim", "fire", "weapon_next", "reload",
]


func _game_actions() -> Array[StringName]:
	var result: Array[StringName] = []
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			result.append(action)
	return result


func test_required_actions_exist() -> void:
	for action in REQUIRED_ACTIONS:
		assert_bool(InputMap.has_action(action)).override_failure_message("missing action %s" % action).is_true()


## Keyboard shortcuts for things a controller reaches another way (named, with the way).
const KEYBOARD_SHORTCUTS: PackedStringArray = [
	"report_open",  # F8; controllers use the pause menu's "Report a problem" or hold Menu
]


func test_every_action_has_a_gamepad_binding() -> void:
	for action in _game_actions():
		if String(action) in KEYBOARD_SHORTCUTS:
			continue
		var has_joypad := false
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				has_joypad = true
		assert_bool(has_joypad).override_failure_message("action %s has no gamepad binding" % action).is_true()


## Actions live at the same time (one context) must not share a button or key; the handbrake
## and the car reset once both sat on RB and every handbrake pull teleported the car. Pairs
## declared as shared in controls.json (R3 tap looks behind, R3 held resets) are the exception.
func test_each_context_uses_distinct_buttons_and_keys() -> void:
	for ctx in Controls.contexts():
		var live := Controls.actions_in(ctx)
		for i in range(live.size()):
			for j in range(i + 1, live.size()):
				if Controls.may_share(live[i], live[j]):
					continue
				for a in InputMap.action_get_events(live[i]):
					for b in InputMap.action_get_events(live[j]):
						assert_bool(Controls.same_input(a, b)).override_failure_message(
							"%s: %s and %s share %s" % [ctx, live[i], live[j], Controls.event_text(a)]).is_false()


func test_every_game_action_is_listed_in_the_controls_data() -> void:
	const MODIFIERS: PackedStringArray = ["debug_modifier"]  # held with others, not an action of its own
	var listed := PackedStringArray()
	for ctx in Controls.data()["contexts"]:
		listed.append_array(Controls.actions_in(ctx))
	for action in _game_actions():
		if String(action) in MODIFIERS:
			continue
		assert_bool(listed.has(String(action))).override_failure_message("%s is not in controls.json" % action).is_true()
	for action in listed:
		assert_bool(InputMap.has_action(action)).override_failure_message("controls.json names unknown action %s" % action).is_true()


func test_layout_matches_the_genre_choices() -> void:
	# design.md of update-controls-layout: GTA V's driving buttons where they agree.
	assert_str(Controls.binding_text("handbrake", true)).is_equal("RB")
	assert_str(Controls.binding_text("horn", true)).is_equal("L3")
	assert_str(Controls.binding_text("look_behind", true)).is_equal("R3")
	assert_str(Controls.binding_text("reset_vehicle", true)).is_equal("R3")
	assert_str(Controls.binding_text("headlights_cycle", true)).is_equal("D-pad right")
	assert_str(Controls.binding_text("radio_cycle", true)).is_equal("D-pad left")
	assert_str(Controls.binding_text("camera_cycle", true)).is_equal("D-pad down")
	assert_str(Controls.binding_text("aim", true)).is_equal("LT")
	assert_str(Controls.binding_text("weapon_next", true)).is_equal("LB")
	assert_str(Controls.binding_text("reload", true)).is_equal("B")
	assert_str(Controls.binding_text("pause", false)).is_equal("Esc")


func test_a_conflicting_binding_is_named() -> void:
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	assert_str(Controls.conflict("horn", rb)).is_equal("handbrake")
	var r3 := InputEventJoypadButton.new()
	r3.button_index = JOY_BUTTON_RIGHT_STICK
	assert_str(Controls.conflict("reset_vehicle", r3)).is_equal("")  # its declared tap/hold partner
	var dpad_up := InputEventJoypadButton.new()
	dpad_up.button_index = JOY_BUTTON_DPAD_UP
	assert_str(Controls.conflict("horn", dpad_up)).is_equal("")
