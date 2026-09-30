extends CanvasLayer
## Debug overlay: fps, frame time, draw calls, active preset.
## Toggle with F3 on keyboard, or hold Back (View) and press X on a gamepad.

const ACTION_MODIFIER := "debug_modifier"
const ACTION_TOGGLE := "debug_toggle"
const SMOOTHING := 0.1

@onready var _label: Label = $Label
var _smoothed_frame_ms: float = 0.0


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION_TOGGLE):
		return
	var is_keyboard := event is InputEventKey
	if is_keyboard or Input.is_action_pressed(ACTION_MODIFIER):
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_smoothed_frame_ms = lerpf(_smoothed_frame_ms, delta * 1000.0, SMOOTHING)
	_label.text = format_stats(
		Engine.get_frames_per_second(),
		_smoothed_frame_ms,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		Settings.current_preset_name,
		Settings.is_steam_deck,
	)


## Builds the overlay text. Pure so it can be tested.
static func format_stats(fps: float, frame_ms: float, draw_calls: int, primitives: int, preset: String, on_deck: bool) -> String:
	return "%d fps  %.1f ms\ndraw calls %d  primitives %d\npreset %s%s" % [
		int(fps), frame_ms, draw_calls, primitives, preset, "  (Steam Deck)" if on_deck else "",
	]
