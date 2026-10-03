class_name PauseMenu
extends CanvasLayer
## Pause screen on the `pause` action (Menu/Start, Escape). Handles its own
## navigation in _input so it works while the tree is paused and with any
## controller mapping: up/down move the selection, A activates, B or Menu resume.
## Holding Menu (or Escape) for REPORT_HOLD_S goes straight to "Report a problem". Opening
## captures the frame under the menu and a frame-time snapshot for the report.

signal resumed
signal quit_requested
signal character_requested
signal host_requested
signal join_requested(address: String)
signal report_requested

@onready var _buttons: Array[Button] = [$Panel/VBox/Resume, $Panel/VBox/Character, $Panel/VBox/Tone, $Panel/VBox/Host, $Panel/VBox/Join, $Panel/VBox/Report, $Panel/VBox/Quit]
const TONE_ROW := 2
const JOIN_ROW := 4
const REPORT_ROW := 5
const QUIT_ROW := 6
## Holding the pause button this long after it opened the menu opens the report form.
const REPORT_HOLD_S := 1.0
@onready var _address: LineEdit = $Panel/VBox/Address
@onready var _players: Label = $Panel/VBox/Players

var overview_map: OverviewMap
var _selected: int = 0
## The frame and frame-time stats from just before the menu opened, for issue reports.
var captured_frame: Image
var captured_frame_stats: Dictionary = {}
var _hold_s: float = -1.0  # time the pause button has been held since it opened the menu; -1 when not held


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_buttons[0].pressed.connect(close)
	_buttons[1].pressed.connect(func() -> void: character_requested.emit())
	_buttons[TONE_ROW].pressed.connect(func() -> void: _cycle_tone(1))
	_buttons[3].pressed.connect(func() -> void: host_requested.emit())
	_buttons[JOIN_ROW].pressed.connect(func() -> void: join_requested.emit(_address.text.strip_edges()))
	_buttons[REPORT_ROW].pressed.connect(func() -> void: report_requested.emit())
	_buttons[QUIT_ROW].pressed.connect(func() -> void: quit_requested.emit())
	_highlight()


## Status line under the buttons: who is in the session, or why a join failed.
func set_status(text: String) -> void:
	_players.text = text


func _input(event: InputEvent) -> void:
	if _address.has_focus() and visible and not event.is_action_pressed("pause"):
		return  # typing an address: keys go to the field, B leaves it
	if event.is_action_pressed("pause"):
		var opening := not visible
		toggle()
		_hold_s = 0.0 if opening else -1.0
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("pause"):
		_hold_s = -1.0
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_accept"):
		_buttons[_selected].pressed.emit()
	elif event.is_action_pressed("ui_right") and _selected == JOIN_ROW:
		_address.grab_focus()  # edit the address with the on-screen keyboard
	elif (event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left")) and _selected == TONE_ROW:
		_cycle_tone(1 if event.is_action_pressed("ui_right") else -1)
	elif event.is_action_pressed("ui_down"):
		_selected = (_selected + 1) % _buttons.size()
		_highlight()
	elif event.is_action_pressed("ui_up"):
		_selected = (_selected - 1 + _buttons.size()) % _buttons.size()
		_highlight()
	else:
		return
	get_viewport().set_input_as_handled()


func _cycle_tone(delta: int) -> void:
	if ContentMode.locked:
		return
	ContentMode.cycle(delta)
	_highlight()


func _tone_text() -> String:
	if ContentMode.locked:
		return "Tone: %s (the host's)" % ContentMode.mode_name()
	return "Tone: <  %s  >" % ContentMode.mode_name()


func _highlight() -> void:
	_buttons[TONE_ROW].text = _tone_text()
	for i in range(_buttons.size()):
		_buttons[i].text = ("> " if i == _selected else "   ") + _buttons[i].text.trim_prefix("> ").trim_prefix("   ")
	_buttons[_selected].grab_focus()


func _process(delta: float) -> void:
	if _hold_s < 0.0 or not visible:
		return
	if not Input.is_action_pressed("pause"):
		_hold_s = -1.0
		return
	_hold_s += delta
	if _hold_s >= REPORT_HOLD_S:
		_hold_s = -1.0
		report_requested.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if overview_map != null and overview_map.visible:
		overview_map.close()
	capture()
	visible = true
	_selected = 0
	_highlight()
	get_tree().paused = true


## Grabs the last drawn frame (the menu is not drawn yet) and the frame-time snapshot.
func capture() -> void:
	captured_frame = null
	# Headless runs (tests, CI) draw nothing: there is no frame, and asking for one only logs an error.
	var tex := get_viewport().get_texture() if DisplayServer.get_name() != "headless" else null
	if tex != null:
		captured_frame = tex.get_image()
	var overlay := get_node_or_null("/root/DebugOverlay")
	captured_frame_stats = overlay.frame_times.stats() if overlay != null else {"avg_ms": 0.0, "p99_ms": 0.0, "seconds": 0.0}


## Shows the menu again over a screen it opened (the creator), keeping the tree paused.
func reopen() -> void:
	visible = true
	_highlight()
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	resumed.emit()
