class_name PauseMenu
extends CanvasLayer
## Pause screen on the `pause` action (Menu/Start, Escape). Handles its own
## navigation in _input so it works while the tree is paused and with any
## controller mapping: up/down move the selection, A activates, B or Menu resume.

signal resumed
signal quit_requested
signal character_requested
signal host_requested
signal join_requested(address: String)

@onready var _buttons: Array[Button] = [$Panel/VBox/Resume, $Panel/VBox/Character, $Panel/VBox/Tone, $Panel/VBox/Host, $Panel/VBox/Join, $Panel/VBox/Quit]
const TONE_ROW := 2
const JOIN_ROW := 4
@onready var _address: LineEdit = $Panel/VBox/Address
@onready var _players: Label = $Panel/VBox/Players

var overview_map: OverviewMap
var _selected: int = 0


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_buttons[0].pressed.connect(close)
	_buttons[1].pressed.connect(func() -> void: character_requested.emit())
	_buttons[TONE_ROW].pressed.connect(func() -> void: _cycle_tone(1))
	_buttons[3].pressed.connect(func() -> void: host_requested.emit())
	_buttons[JOIN_ROW].pressed.connect(func() -> void: join_requested.emit(_address.text.strip_edges()))
	_buttons[5].pressed.connect(func() -> void: quit_requested.emit())
	_highlight()


## Status line under the buttons: who is in the session, or why a join failed.
func set_status(text: String) -> void:
	_players.text = text


func _input(event: InputEvent) -> void:
	if _address.has_focus() and visible and not event.is_action_pressed("pause"):
		return  # typing an address: keys go to the field, B leaves it
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()
		return
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


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if overview_map != null and overview_map.visible:
		overview_map.close()
	visible = true
	_selected = 0
	_highlight()
	get_tree().paused = true


## Shows the menu again over a screen it opened (the creator), keeping the tree paused.
func reopen() -> void:
	visible = true
	_highlight()
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	resumed.emit()
