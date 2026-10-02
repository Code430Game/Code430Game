class_name CharacterCreator
extends CanvasLayer
## Character creator: rows for each profile field, a preview, presets. Opened from the pause
## menu while the tree is paused; works with any controller mapping through the ui_* actions.
## The live player follows every change (profile_changed); Done stores "last" and closes.

signal profile_changed(profile: Dictionary)
signal closed(profile: Dictionary)

const FIELD_ROWS: Array = [
	["skin", "Skin"], ["hair", "Hair"], ["hair_colour", "Hair colour"], ["top", "Top"],
	["jacket", "Jacket"], ["jacket_colour", "Jacket colour"], ["bottom", "Trousers"], ["shoes", "Shoes"],
	["hat", "Hat"], ["beard", "Beard"], ["glasses", "Glasses"], ["height", "Height"], ["build", "Build"],
]
const ACTION_ROWS: Array = [
	["randomise", "Randomise"], ["preset", "Preset"], ["save", "Save as a new preset"],
	["delete", "Delete that preset"], ["done", "Done"],
]
const PREVIEW_TURN_RAD_S := 0.6

## Where presets live; tests point this at a temp file.
var store_path: String = CharacterStore.DEFAULT_PATH
var profile: Dictionary = {}

@onready var _rows_box: VBoxContainer = $Panel/HBox/Left/Rows
@onready var _status: Label = $Panel/HBox/Left/Status
@onready var _preview: Node3D = $Panel/HBox/ViewportContainer/Viewport/Body
var _rig: CharacterRig = null
@onready var _camera: Camera3D = $Panel/HBox/ViewportContainer/Viewport/Camera

var _rows: Array[Label] = []  # value column
var _names: Array[Label] = []  # name column, carries the selection marker
var _selected: int = 0
var _presets: Array = []
var _preset_index: int = -1


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	for row: Array in FIELD_ROWS + ACTION_ROWS:
		var line := HBoxContainer.new()
		var n := Label.new()
		n.add_theme_font_size_override("font_size", 17)
		n.custom_minimum_size.x = 150.0
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 17)
		line.add_child(n)
		line.add_child(l)
		_rows_box.add_child(line)
		_names.append(n)
		_rows.append(l)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.13, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.6
	_camera.environment = env


func open(start: Dictionary) -> void:
	profile = CharacterProfile.normalise(start)
	_presets = CharacterStore.presets(store_path)
	_preset_index = -1 if _presets.is_empty() else 0
	_selected = 0
	_status.text = ""
	visible = true
	get_tree().paused = true
	_apply()


func _apply() -> void:
	if _rig == null:
		_rig = CharacterRig.new()
		_rig.profile = profile
		_preview.add_child(_rig)
	else:
		_rig.apply_profile(profile)
	_refresh()
	profile_changed.emit(profile)


func _refresh() -> void:
	var rows: Array = FIELD_ROWS + ACTION_ROWS
	for i in range(rows.size()):
		var key: String = rows[i][0]
		_names[i].text = ("> " if i == _selected else "   ") + str(rows[i][1])
		var value := ""
		if i < FIELD_ROWS.size():
			value = "<  %s  >" % CharacterProfile.label(profile, key)
		elif key == "preset":
			value = "<  %s  >   A loads" % _preset_name()
		_rows[i].text = value


func _preset_name() -> String:
	if _preset_index < 0 or _preset_index >= _presets.size():
		return "none saved"
	return str((_presets[_preset_index] as Dictionary).get("name", "?"))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var rows: Array = FIELD_ROWS + ACTION_ROWS
	var key: String = rows[_selected][0]
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_done()
	elif event.is_action_pressed("ui_down"):
		_selected = (_selected + 1) % rows.size()
		_refresh()
	elif event.is_action_pressed("ui_up"):
		_selected = (_selected - 1 + rows.size()) % rows.size()
		_refresh()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		var delta := 1 if event.is_action_pressed("ui_right") else -1
		if _selected < FIELD_ROWS.size():
			profile = CharacterProfile.step(profile, key, delta)
			_apply()
		elif key == "preset" and not _presets.is_empty():
			_preset_index = posmod(_preset_index + delta, _presets.size())
			_refresh()
	elif event.is_action_pressed("ui_accept"):
		_activate(key)
	elif not event.is_pressed():
		return
	get_viewport().set_input_as_handled()


func _activate(key: String) -> void:
	match key:
		"randomise":
			profile = CharacterProfile.random()
			_status.text = "random body"
			_apply()
		"preset":
			if _preset_index >= 0 and _preset_index < _presets.size():
				profile = CharacterProfile.normalise((_presets[_preset_index] as Dictionary)["profile"])
				_status.text = "loaded %s" % _preset_name()
				_apply()
		"save":
			var name := CharacterStore.save_preset(profile, "", store_path)
			_presets = CharacterStore.presets(store_path)
			_preset_index = _presets.size() - 1
			_status.text = "saved as %s" % name
			_refresh()
		"delete":
			if _preset_index >= 0 and _preset_index < _presets.size():
				var gone := _preset_name()
				CharacterStore.delete_preset(gone, store_path)
				_presets = CharacterStore.presets(store_path)
				_preset_index = -1 if _presets.is_empty() else mini(_preset_index, _presets.size() - 1)
				_status.text = "deleted %s" % gone
				_refresh()
		"done":
			_done()
		_:
			if _selected < FIELD_ROWS.size():
				profile = CharacterProfile.step(profile, key, 1)
				_apply()


func _done() -> void:
	CharacterStore.save_last(profile, store_path)
	visible = false
	closed.emit(profile)


func _process(delta: float) -> void:
	if visible:
		_preview.rotation.y += PREVIEW_TURN_RAD_S * delta
		if _rig != null:
			_rig.advance(delta, 1.0)  # walks on the spot
