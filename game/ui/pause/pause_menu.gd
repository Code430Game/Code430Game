class_name PauseMenu
extends CanvasLayer
## Pause screen on the `pause` action (Menu/Start, Escape). A resumes, the Quit
## button quits. Pauses the tree while open; closes the overview map if it is open.

signal resumed
signal quit_requested

@onready var _resume: Button = $Panel/VBox/Resume
@onready var _quit: Button = $Panel/VBox/Quit

var overview_map: OverviewMap


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resume.pressed.connect(close)
	_quit.pressed.connect(func() -> void: quit_requested.emit())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if overview_map != null and overview_map.visible:
		overview_map.close()
	visible = true
	get_tree().paused = true
	_resume.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false
	resumed.emit()
