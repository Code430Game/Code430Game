class_name CharacterCreator
extends CanvasLayer
## Character creator: rows for each profile field, a preview, presets. Opened from the pause
## menu while the tree is paused; works with any controller mapping through the ui_* actions.
## The live player follows every change (profile_changed); Done stores "last" and closes. The
## look comes from MenuTheme (update-menu-design): rows are compact panels, the selected one
## filled with the tone's accent.

signal profile_changed(profile: Dictionary)
signal closed(profile: Dictionary)

const FIELD_ROWS: Array = [
	["skin", "Skin"], ["hair", "Hair"], ["hair_colour", "Hair colour"], ["top", "Top"],
	["jacket", "Jacket"], ["jacket_colour", "Jacket colour"], ["bottom", "Trousers"], ["shoes", "Shoes"],
	["hat", "Hat"], ["beard", "Beard"], ["glasses", "Glasses"], ["body", "body.label"], ["height", "Height"], ["build", "Build"],
]
const ACTION_ROWS: Array = [
	["randomise", "Randomise"], ["preset", "Preset"], ["save", "Save as a new preset"],
	["delete", "Delete that preset"], ["done", "Done"],
]
const PREVIEW_TURN_RAD_S := 0.6
const NAME_COLUMN_PX := 170.0

## Where presets live; tests point this at a temp file.
var store_path: String = CharacterStore.DEFAULT_PATH
var profile: Dictionary = {}

@onready var _rows_box: VBoxContainer = $Panel/HBox/Left/Rows
@onready var _status: Label = $Panel/HBox/Left/Status
@onready var _hint: HBoxContainer = $Panel/HBox/Left/Footer/Hint
@onready var _preview: Node3D = $Panel/HBox/ViewportContainer/Viewport/Body
var _rig: CharacterRig = null
@onready var _camera: Camera3D = $Panel/HBox/ViewportContainer/Viewport/Camera

var _rows: Array[Label] = []  # value column
var _names: Array[Label] = []  # name column
var _lines: Array[PanelContainer] = []  # one row each, selected one filled
var _selected: int = 0
var _presets: Array = []
var _preset_index: int = -1


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	($Panel as Control).theme = MenuTheme.theme()
	for row: Array in FIELD_ROWS + ACTION_ROWS:
		if row == ACTION_ROWS[0]:
			var gap := Control.new()  # the actions read as their own group below the body rows
			gap.custom_minimum_size.y = MenuTheme.num(MenuTheme.theme().get_meta("data", {}), "spacing", "section_gap", 14)
			_rows_box.add_child(gap)
		var panel := PanelContainer.new()
		MenuTheme.set_selected(panel, false, true)
		var line := HBoxContainer.new()
		var n := Label.new()
		n.custom_minimum_size.x = NAME_COLUMN_PX
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(n)
		line.add_child(l)
		panel.add_child(line)
		_rows_box.add_child(panel)
		_lines.append(panel)
		_names.append(n)
		_rows.append(l)
	MenuTheme.hint_bar(_hint, [["Up / Down", "row"], ["Left / Right", "change"], ["A", "select"], ["B", "done"]])
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.13, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.6
	_camera.environment = env


func open(start: Dictionary) -> void:
	profile = CharacterProfile.normalise(start)
	_presets = all_presets(store_path)
	_preset_index = -1 if _presets.is_empty() else 0
	_selected = 0
	_status.text = ""
	MenuTheme.refresh_accent()
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
		_names[i].text = ContentMode.text(str(rows[i][1])) if str(rows[i][1]).contains(".") else str(rows[i][1])
		MenuTheme.set_selected(_lines[i], i == _selected, true)
		var value := ""
		if i < FIELD_ROWS.size():
			value = "<  %s  >" % CharacterProfile.label(profile, key)
		elif key == "preset":
			value = "<  %s  >   A loads" % _preset_name()
		_rows[i].text = value


func _preset_name() -> String:
	if _preset_index < 0 or _preset_index >= _presets.size():
		return "none saved"
	var p: Dictionary = _presets[_preset_index]
	return str(p.get("name", "?")) + ("  (pack)" if p.has("pack_id") else "")


## The player's saved presets first, then every enabled character pack's named presets
## (add-pack-loader 3.1); pack presets carry `pack_id` and cannot be deleted here.
static func all_presets(path: String) -> Array:
	var out: Array = CharacterStore.presets(path)
	var loader: Node = Engine.get_main_loop().root.get_node_or_null("PackLoader") if Engine.get_main_loop() is SceneTree else null
	if loader == null:
		return out
	for item: Dictionary in loader.call("items", "presets"):
		if item.get("profile") is Dictionary:
			out.append({"name": str(item.get("name", "preset")), "profile": CharacterProfile.normalise(item["profile"]), "pack_id": str(item.get("pack_id", ""))})
	return out


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
			_presets = all_presets(store_path)
			_preset_index = CharacterStore.presets(store_path).size() - 1
			_status.text = "saved as %s" % name
			_refresh()
		"delete":
			if _preset_index >= 0 and _preset_index < _presets.size():
				var chosen: Dictionary = _presets[_preset_index]
				if chosen.has("pack_id"):
					_status.text = "%s comes with a pack; disable the pack to remove it" % str(chosen.get("name", "?"))
					_refresh()
					return
				var gone := str(chosen.get("name", "?"))
				CharacterStore.delete_preset(gone, store_path)
				_presets = all_presets(store_path)
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
