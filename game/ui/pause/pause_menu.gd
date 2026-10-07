class_name PauseMenu
extends CanvasLayer
## Pause screen on the `pause` action (Menu/Start, Escape), in tabs: Game (resume, character,
## report, quit), Co-op (host, join at an address, who is in the session), Controls (every action for the device in use, press A to rebind),
## Options (tone, music volume) and Settings (graphics). LB/RB or Q/E change tab. Handles its
## own navigation in _input so it works while the tree is paused and with any controller
## mapping: up/down move the selection, left/right change a value, A activates, B or Menu
## resume. Holding Menu (or Escape) for REPORT_HOLD_S goes straight to "Report a problem".
## Opening captures the frame under the menu and a frame-time snapshot for the report. The look
## comes from MenuTheme (update-menu-design): the selected row is filled with the tone's accent,
## hints sit in a footer as key caps.

signal resumed
signal quit_requested
signal character_requested
signal host_requested
signal join_requested(address: String)
signal report_requested

const TABS: PackedStringArray = ["Game", "Co-op", "Controls", "Options", "Settings"]
const GAME_TAB := 0
const COOP_TAB := 1
const CONTROLS_TAB := 2
const OPTIONS_TAB := 3
const SETTINGS_TAB := 4
## Rows of the Game tab.
const REPORT_ROW := 2
const QUIT_ROW := 3
## Rows of the Co-op tab.
const HOST_ROW := 0
const JOIN_ROW := 1
## Holding the pause button this long after it opened the menu opens the report form.
const REPORT_HOLD_S := 1.0
const MUSIC_STEP_DB := 2.0
const MUSIC_MIN_DB := -40.0
const MUSIC_MAX_DB := 6.0
const PRESETS: PackedStringArray = ["auto", "deck", "high"]

@onready var _address: LineEdit = $Panel/VBox/Pages/Coop/Address
@onready var _players: Label = $Panel/VBox/Pages/Coop/Players
@onready var _tab_bar: HBoxContainer = $Panel/VBox/TabStrip/Tabs
@onready var _hint: HBoxContainer = $Panel/VBox/Footer/Hint
@onready var _pages_root: Control = $Panel/VBox/Pages

var overview_map: OverviewMap
## The radio whose music volume the Options tab sets (the scene hands it over).
var radio: Radio
var tab: int = GAME_TAB
## Controller layout on the Controls tab, or keyboard and mouse; follows the last input.
var showing_pad: bool = true
## The action waiting for a press on the Controls tab, or "".
var capturing: String = ""
## The frame and frame-time stats from just before the menu opened, for issue reports.
var captured_frame: Image
var captured_frame_stats: Dictionary = {}

var _pages: Array[Control] = []
var _rows: Array = []  # per tab: Array[Button]
var _selected: PackedInt32Array = [0, 0, 0, 0, 0]
var _tab_labels: Array[Button] = []
var _controls_list: VBoxContainer
var _controls_scroll: ScrollContainer
var _controls_note: Label
var _device_label: Label
var _hold_s: float = -1.0  # time the pause button has been held since it opened the menu; -1 when not held


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	($Panel as Control).theme = MenuTheme.theme()
	var game: Array[Button] = [$Panel/VBox/Pages/Game/Resume, $Panel/VBox/Pages/Game/Character, $Panel/VBox/Pages/Game/Report, $Panel/VBox/Pages/Game/Quit]
	game[0].pressed.connect(close)
	game[1].pressed.connect(func() -> void: character_requested.emit())
	game[REPORT_ROW].pressed.connect(func() -> void: report_requested.emit())
	game[QUIT_ROW].pressed.connect(func() -> void: quit_requested.emit())
	var coop: Array[Button] = [$Panel/VBox/Pages/Coop/Host, $Panel/VBox/Pages/Coop/Join]
	coop[HOST_ROW].pressed.connect(func() -> void: host_requested.emit())
	coop[JOIN_ROW].pressed.connect(func() -> void: join_requested.emit(_address.text.strip_edges()))
	_pages = [$Panel/VBox/Pages/Game, $Panel/VBox/Pages/Coop, _build_controls_page(), _build_options_page(), _build_settings_page()]
	_rows = [game, coop, [], [], []]
	for i in range(TABS.size()):
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = MenuTheme.TAB
		b.pressed.connect(show_tab.bind(i))
		_tab_bar.add_child(b)
		_tab_labels.append(b)
	_rebuild_controls()
	_rebuild_options()
	_rebuild_settings()
	show_tab(GAME_TAB)


## Status line under the buttons: who is in the session, or why a join failed.
func set_status(text: String) -> void:
	_players.text = text


## The buttons of a tab, top to bottom (tests and the testbed).
func rows(of_tab: int) -> Array:
	return _rows[of_tab]


func selected_row() -> int:
	return _selected[tab]


func show_tab(index: int) -> void:
	tab = posmod(index, TABS.size())
	capturing = ""
	for i in range(_pages.size()):
		_pages[i].visible = i == tab
		_tab_labels[i].button_pressed = i == tab
	if tab == CONTROLS_TAB:
		_rebuild_controls()
	_update_hint()
	_highlight()


func _input(event: InputEvent) -> void:
	if capturing != "" and visible:
		_capture(event)
		return
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
	_note_device(event)
	if _is_tab_press(event, true):
		show_tab(tab + 1)
	elif _is_tab_press(event, false):
		show_tab(tab - 1)
	elif event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_accept"):
		var row: Array = _rows[tab]
		if not row.is_empty():
			(row[_selected[tab]] as Button).pressed.emit()
	elif event.is_action_pressed("ui_right") and tab == COOP_TAB and _selected[tab] == JOIN_ROW:
		_address.grab_focus()  # edit the address with the on-screen keyboard
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		var row: Array = _rows[tab]
		if row.is_empty():
			return
		var b: Button = row[_selected[tab]]
		if b.has_meta("step"):
			(b.get_meta("step") as Callable).call(1 if event.is_action_pressed("ui_right") else -1)
		else:
			return
	elif event.is_action_pressed("ui_down"):
		_move(1)
	elif event.is_action_pressed("ui_up"):
		_move(-1)
	else:
		return
	get_viewport().set_input_as_handled()


## LB/RB on a controller, Q/E on the keyboard: fixed menu buttons, whatever the game bindings.
static func _is_tab_press(event: InputEvent, next: bool) -> bool:
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == (JOY_BUTTON_RIGHT_SHOULDER if next else JOY_BUTTON_LEFT_SHOULDER)
	if event is InputEventKey and event.pressed and not event.echo:
		return (event as InputEventKey).physical_keycode == (KEY_E if next else KEY_Q)
	return false


func _note_device(event: InputEvent) -> void:
	var pad := showing_pad
	if Controls.is_key_event(event):
		pad = false
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.3):
		pad = true
	if pad != showing_pad:
		showing_pad = pad
		_update_hint()
		if tab == CONTROLS_TAB:
			_rebuild_controls()
			_highlight()


func _update_hint() -> void:
	var tabs := ["LB / RB" if showing_pad else "Q / E", "tabs"]
	var back := ["B" if showing_pad else "Esc", "resume"]
	var accept := "A" if showing_pad else "Enter"
	match tab:
		CONTROLS_TAB:
			MenuTheme.hint_bar(_hint, [tabs, [accept, "rebind"], back])
		OPTIONS_TAB, SETTINGS_TAB:
			MenuTheme.hint_bar(_hint, [tabs, ["Left / Right", "change"], back])
		_:
			MenuTheme.hint_bar(_hint, [tabs, [accept, "select"], back, ["View" if showing_pad else "M", "map"]])


## The footer's hints as plain text (tests).
func hint_text() -> String:
	return MenuTheme.hint_text(_hint)


func _move(delta: int) -> void:
	var row: Array = _rows[tab]
	if row.is_empty():
		return
	_selected[tab] = posmod(_selected[tab] + delta, row.size())
	_highlight()


func _highlight() -> void:
	var row: Array = _rows[tab]
	if row.is_empty():
		return
	_selected[tab] = clampi(_selected[tab], 0, row.size() - 1)
	for i in range(row.size()):
		MenuTheme.set_selected(row[i] as Button, i == _selected[tab])
	var current: Button = row[_selected[tab]]
	if visible and current.is_visible_in_tree():
		current.grab_focus()
	if tab == CONTROLS_TAB and _controls_scroll != null:
		_controls_scroll.ensure_control_visible.call_deferred(current)


func _row_button(text: String) -> Button:
	var b := Button.new()
	b.set_meta("text", text)
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.theme_type_variation = MenuTheme.ROW
	return b


func _set_text(b: Button, text: String) -> void:
	b.set_meta("text", text)
	b.text = text


# --- Controls tab ---

func _build_controls_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "Controls"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 8)
	_device_label = Label.new()
	_device_label.theme_type_variation = MenuTheme.NOTE
	_device_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_device_label)
	_controls_scroll = ScrollContainer.new()
	_controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(MenuTheme.scroll_frame(_controls_scroll))
	var gutter := MarginContainer.new()  # keeps the key caps clear of the scrollbar
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", int(MenuTheme.num(MenuTheme.theme().get_meta("data", {}), "spacing", "scroll_gutter", 12)))
	_controls_scroll.add_child(gutter)
	_controls_list = VBoxContainer.new()
	_controls_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls_list.add_theme_constant_override("separation", 2)
	gutter.add_child(_controls_list)
	_controls_note = Label.new()
	_controls_note.theme_type_variation = MenuTheme.NOTE
	_controls_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_controls_note)
	_pages_root.add_child(page)
	return page


## Lists every action of each context for the device in use; rows that can be rebound press
## into capture mode, the last row resets every binding.
func _rebuild_controls() -> void:
	if _controls_list == null:
		return
	var keep := _selected[CONTROLS_TAB]
	for c in _controls_list.get_children():
		_controls_list.remove_child(c)
		c.queue_free()
	_device_label.text = "Showing the %s layout (switches with the last thing you pressed)" % ("controller" if showing_pad else "keyboard and mouse")
	var buttons: Array[Button] = []
	for ctx: String in ["foot", "drive", Controls.ANY, "debug"]:
		var heading := Label.new()
		heading.text = Controls.context_label(ctx)
		heading.theme_type_variation = MenuTheme.HEADING
		_controls_list.add_child(heading)
		for row in Controls.rows(ctx):
			var b := _binding_row(row)
			_controls_list.add_child(b)
			buttons.append(b)
	var reset := _row_button("Reset all controls to the defaults")
	reset.pressed.connect(_reset_controls)
	_controls_list.add_child(reset)
	buttons.append(reset)
	_rows[CONTROLS_TAB] = buttons
	_selected[CONTROLS_TAB] = clampi(keep, 0, buttons.size() - 1)


func _binding_row(row: Dictionary) -> Button:
	var b := _row_button(str(row["label"]))
	b.add_theme_font_size_override("font_size", int(MenuTheme.num(MenuTheme.theme().get_meta("data", {}), "fonts", "body", 18)))
	var binding := MenuTheme.key_cap(Controls.row_text(row, showing_pad))
	# Pinned to the row's right edge, growing leftwards to fit its text.
	binding.anchor_left = 1.0
	binding.anchor_right = 1.0
	binding.anchor_top = 0.5
	binding.anchor_bottom = 0.5
	binding.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	binding.grow_vertical = Control.GROW_DIRECTION_BOTH
	binding.offset_left = -12.0
	binding.offset_right = -12.0
	binding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(binding)
	b.set_meta("binding", binding)
	var action := str(row.get("action", ""))
	var fixed := row.has("pad" if showing_pad else "key")
	if action != "" and not fixed and Controls.rebindable(action):
		b.set_meta("action", action)
		b.pressed.connect(_start_capture.bind(b))
	else:
		b.pressed.connect(func() -> void: _controls_note.text = "%s can't be changed here." % str(row["label"]).capitalize())
	return b


func _start_capture(b: Button) -> void:
	capturing = str(b.get_meta("action"))
	(b.get_meta("binding") as Label).text = "press a %s...  (%s cancels)" % ["button" if showing_pad else "key", "Menu" if showing_pad else "Esc"]
	_controls_note.text = "Rebinding %s." % Controls.label(capturing)


## While capturing: the next press of the device shown becomes the binding, unless it clashes.
## The pause button cancels. Releases, stick wiggles and the other device are ignored.
func _capture(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("pause"):
		_controls_note.text = "Kept %s as it was." % Controls.label(capturing)
		capturing = ""
		_rebuild_controls()
		_highlight()
		return
	var press: InputEvent = null
	if showing_pad:
		if event is InputEventJoypadButton and event.pressed:
			press = event
		elif event is InputEventJoypadMotion:
			var m := event as InputEventJoypadMotion
			if (m.axis == JOY_AXIS_TRIGGER_LEFT or m.axis == JOY_AXIS_TRIGGER_RIGHT) and m.axis_value > 0.6:
				press = Controls.event_from_dict({"type": "axis", "axis": m.axis, "value": 1.0})
	elif (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		press = event
	if press == null:
		return
	if press is InputEventJoypadButton:
		press = Controls.event_from_dict(Controls.event_to_dict(press))  # drop device and pressure
	elif press is InputEventKey:
		press = Controls.event_from_dict(Controls.event_to_dict(press))
	var action := capturing
	capturing = ""
	var clash := Settings.rebind(action, press)
	if clash != "":
		_controls_note.text = "%s is already used for %s. Nothing changed." % [Controls.event_text(press), clash]
	else:
		_controls_note.text = "%s is now %s." % [Controls.label(action).capitalize(), Controls.event_text(press)]
	_rebuild_controls()
	_highlight()


func _reset_controls() -> void:
	Settings.reset_bindings()
	_controls_note.text = "Every control is back to its default."
	_rebuild_controls()
	_highlight()


# --- Options tab ---

func _build_options_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "Options"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 6)
	_pages_root.add_child(page)
	return page


func _rebuild_options() -> void:
	var page := _pages[OPTIONS_TAB]
	if (_rows[OPTIONS_TAB] as Array).is_empty():
		var tone := _row_button("")
		tone.set_meta("step", func(d: int) -> void: _cycle_tone(d))
		tone.pressed.connect(func() -> void: _cycle_tone(1))
		var music := _row_button("")
		music.set_meta("step", func(d: int) -> void: _step_music(d))
		page.add_child(tone)
		page.add_child(music)
		_rows[OPTIONS_TAB] = [tone, music]
	var rows_now: Array = _rows[OPTIONS_TAB]
	_set_text(rows_now[0], _tone_text())
	var music_text := "Music volume: <  %+.0f dB  >" % radio.music_volume_db if radio != null else "Music volume: (radio not running)"
	_set_text(rows_now[1], music_text)


func _cycle_tone(delta: int) -> void:
	if ContentMode.locked:
		return
	ContentMode.cycle(delta)
	MenuTheme.refresh_accent()
	_rebuild_options()
	_highlight()


func _tone_text() -> String:
	if ContentMode.locked:
		return "Tone: %s (the host's)" % ContentMode.mode_name()
	return "Tone: <  %s  >" % ContentMode.mode_name()


func _step_music(delta: int) -> void:
	if radio == null:
		return
	radio.set_music_volume_db(clampf(radio.music_volume_db + delta * MUSIC_STEP_DB, MUSIC_MIN_DB, MUSIC_MAX_DB))
	_rebuild_options()
	_highlight()


# --- Settings tab ---

func _build_settings_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "Settings"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 6)
	_pages_root.add_child(page)
	return page


func _rebuild_settings() -> void:
	var page := _pages[SETTINGS_TAB]
	if (_rows[SETTINGS_TAB] as Array).is_empty():
		var graphics := _row_button("")
		graphics.set_meta("step", func(d: int) -> void: _step_preset(d))
		graphics.pressed.connect(func() -> void: _step_preset(1))
		page.add_child(graphics)
		var note := Label.new()
		note.name = "Note"
		note.theme_type_variation = MenuTheme.NOTE
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.add_child(note)
		_rows[SETTINGS_TAB] = [graphics]
	var current := Settings.preset_override
	var shown := "Auto (%s)" % Settings.resolve_preset_name().capitalize() if current == Settings.PRESET_AUTO else current.capitalize()
	_set_text(_rows[SETTINGS_TAB][0], "Graphics: <  %s  >" % shown)
	(page.get_node("Note") as Label).text = "Auto picks Deck on a Steam Deck (%s here) and High elsewhere. Saved for next time." % ("detected" if Settings.is_steam_deck else "not detected")


func _step_preset(delta: int) -> void:
	var i := PRESETS.find(Settings.preset_override)
	Settings.set_preset_override(PRESETS[posmod(maxi(i, 0) + delta, PRESETS.size())])
	_rebuild_settings()
	_highlight()


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
	MenuTheme.refresh_accent()
	visible = true
	_selected = PackedInt32Array([0, 0, 0, 0, 0])
	_rebuild_options()
	_rebuild_settings()
	show_tab(GAME_TAB)
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
	capturing = ""
	get_tree().paused = false
	resumed.emit()
