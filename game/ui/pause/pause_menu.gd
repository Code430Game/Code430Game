class_name PauseMenu
extends CanvasLayer
## Pause screen on the `pause` action (Menu/Start, Escape). Handles its own
## navigation in _input so it works while the tree is paused and with any
## controller mapping: up/down move the selection, A activates, B or Menu resume.

signal resumed
signal quit_requested

@onready var _buttons: Array[Button] = [$Panel/VBox/Resume, $Panel/VBox/Quit]

var overview_map: OverviewMap
var _selected: int = 0


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_buttons[0].pressed.connect(close)
	_buttons[1].pressed.connect(func() -> void: quit_requested.emit())
	_highlight()


func _input(event: InputEvent) -> void:
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
	elif event.is_action_pressed("ui_down"):
		_selected = (_selected + 1) % _buttons.size()
		_highlight()
	elif event.is_action_pressed("ui_up"):
		_selected = (_selected - 1 + _buttons.size()) % _buttons.size()
		_highlight()
	else:
		return
	get_viewport().set_input_as_handled()


func _highlight() -> void:
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


func close() -> void:
	visible = false
	get_tree().paused = false
	resumed.emit()
