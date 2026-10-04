extends GdUnitTestSuite
## Every game action must be reachable with a gamepad alone (AGENTS.md, controller-first).

const REQUIRED_ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right",
	"look_up", "look_down", "look_left", "look_right",
	"sprint", "jump", "interact", "accelerate", "brake", "handbrake", "pause",
	"debug_modifier", "debug_toggle", "debug_graph", "reset_vehicle", "map_toggle", "radio_cycle",
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


## Actions that are live at the same time while driving must not share a gamepad button;
## the handbrake and the car reset once both sat on RB and every handbrake pull teleported the car.
func test_driving_actions_use_distinct_buttons() -> void:
	const DRIVING_ACTIONS: PackedStringArray = [
		"accelerate", "brake", "handbrake", "reset_vehicle", "camera_cycle", "headlights_cycle", "interact", "pause", "map_toggle", "radio_cycle",
	]
	var owner_by_button: Dictionary = {}
	for action in DRIVING_ACTIONS:
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				var button: int = (event as InputEventJoypadButton).button_index
				assert_bool(owner_by_button.has(button)).override_failure_message(
					"%s and %s share gamepad button %d" % [owner_by_button.get(button, ""), action, button]).is_false()
				owner_by_button[button] = action
