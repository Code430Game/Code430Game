extends GdUnitTestSuite
## Every game action must be reachable with a gamepad alone (AGENTS.md, controller-first).

const REQUIRED_ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right",
	"look_up", "look_down", "look_left", "look_right",
	"sprint", "jump", "interact", "accelerate", "brake", "handbrake", "pause",
	"debug_modifier", "debug_toggle", "debug_graph", "reset_vehicle",
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


func test_every_action_has_a_gamepad_binding() -> void:
	for action in _game_actions():
		var has_joypad := false
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				has_joypad = true
		assert_bool(has_joypad).override_failure_message("action %s has no gamepad binding" % action).is_true()
