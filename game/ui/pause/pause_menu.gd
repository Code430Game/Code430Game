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

const TABS: PackedStringArray = ["Game", "Co-op", "Controls", "Options", "Settings", "Packs", "Testing"]
const GAME_TAB := 0
const COOP_TAB := 1
const CONTROLS_TAB := 2
const OPTIONS_TAB := 3
const SETTINGS_TAB := 4
const PACKS_TAB := 5
const TESTING_TAB := 6  # only with Tester options on (add-world-menu)
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
## The Testing tab's choices: "auto" leaves the weather table or the clock running.
const TEST_HOURS: PackedFloat32Array = [-1.0, 6.0, 9.0, 12.0, 17.0, 20.0, 22.0, 2.0]
const TEST_DAY_MINUTES: PackedFloat32Array = [6.0, 12.0, 24.0, 48.0, 96.0]

@onready var _address: LineEdit = $Panel/VBox/Pages/Coop/Address
@onready var _players: Label = $Panel/VBox/Pages/Coop/Players
@onready var _tab_bar: HBoxContainer = $Panel/VBox/TabStrip/Tabs
@onready var _hint: HBoxContainer = $Panel/VBox/Footer/Hint
@onready var _pages_root: Control = $Panel/VBox/Pages

## The map pack waiting for a second press before the game restarts on it ("" for none).
var _map_confirm: String = ""
## What the second press calls: a restart on the saved map (tests swap it).
var restart_game: Callable = PauseMenu.restart_with_saved_map
var overview_map: OverviewMap
## The radio whose music volume the Options tab sets (the scene hands it over).
var radio: Radio
## What the Testing tab changes (the scene hands them over); a guest's mirror the host.
var weather: WeatherController
var day_night: DayNight
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
var _selected: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])  # one per tab in TABS
var _tab_labels: Array[Button] = []
var _controls_list: VBoxContainer
var _controls_scroll: ScrollContainer
var _controls_note: Label
var _device_label: Label
var _packs_list: VBoxContainer
var _packs_scroll: ScrollContainer
var _packs_note: Label
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
	_pages = [$Panel/VBox/Pages/Game, $Panel/VBox/Pages/Coop, _build_controls_page(), _build_options_page(), _build_settings_page(), _build_packs_page(), _build_testing_page()]
	_rows = [game, coop, [], [], [], [], []]
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
	_rebuild_testing()
	show_tab(GAME_TAB)


## Status line under the buttons: who is in the session, or why a join failed.
func set_status(text: String) -> void:
	_players.text = text


## The buttons of a tab, top to bottom (tests and the testbed).
func rows(of_tab: int) -> Array:
	return _rows[of_tab]


func selected_row() -> int:
	return _selected[tab]


## Shows tab `index`; a hidden tab (Testing, while Tester options is off) is passed over in the
## direction `dir` that LB/RB moved.
func show_tab(index: int, dir: int = 1) -> void:
	tab = posmod(index, TABS.size())
	if tab == TESTING_TAB and not Settings.tester():
		tab = posmod(tab + (1 if dir >= 0 else -1), TABS.size())
	capturing = ""
	for i in range(_pages.size()):
		_pages[i].visible = i == tab
		_tab_labels[i].button_pressed = i == tab
		_tab_labels[i].visible = i != TESTING_TAB or Settings.tester()
	if tab == CONTROLS_TAB:
		_rebuild_controls()
	elif tab == PACKS_TAB:
		_rebuild_packs()
	elif tab == TESTING_TAB:
		_rebuild_testing()
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
		show_tab(tab - 1, -1)
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
		PACKS_TAB:
			MenuTheme.hint_bar(_hint, [tabs, [accept, "enable / disable"], back])
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
	elif tab == PACKS_TAB and _packs_scroll != null:
		_packs_scroll.ensure_control_visible.call_deferred(current)


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
	for ctx: String in ["foot", "drive", "fly", Controls.ANY, "debug"]:
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
		var tester := _row_button("")
		tester.set_meta("step", func(_d: int) -> void: _toggle_tester())
		tester.pressed.connect(_toggle_tester)
		page.add_child(tester)
		var note := Label.new()
		note.name = "Note"
		note.theme_type_variation = MenuTheme.NOTE
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.add_child(note)
		_rows[SETTINGS_TAB] = [graphics, tester]
	var current := Settings.preset_override
	var shown := "Auto (%s)" % Settings.resolve_preset_name().capitalize() if current == Settings.PRESET_AUTO else current.capitalize()
	_set_text(_rows[SETTINGS_TAB][0], "Graphics: <  %s  >" % shown)
	var tester_text := "On" if Settings.tester_options else "Off"
	if Settings.tester_for_run and not Settings.tester_options:
		tester_text = "On for this run (--tester)"
	_set_text(_rows[SETTINGS_TAB][1], "Tester options: <  %s  >" % tester_text)
	(page.get_node("Note") as Label).text = "Auto picks Deck on a Steam Deck (%s here) and High elsewhere. Tester options adds a Testing tab (weather, time) and Go to (Y) on the map's places. Saved for next time." % ("detected" if Settings.is_steam_deck else "not detected")


func _step_preset(delta: int) -> void:
	var i := PRESETS.find(Settings.preset_override)
	Settings.set_preset_override(PRESETS[posmod(maxi(i, 0) + delta, PRESETS.size())])
	_rebuild_settings()
	_highlight()


## Tester options on or off: shows or hides the Testing tab and the legend's "Go to". Saved.
func _toggle_tester() -> void:
	Settings.tester_options = not Settings.tester_options
	Settings.save_settings()
	if not Settings.tester():
		_release_testing()
	_rebuild_settings()
	show_tab(tab)


# --- Testing tab (add-world-menu) ---

func _build_testing_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "Testing"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 6)
	_pages_root.add_child(page)
	return page


## The weather choices: Auto, then every state in the table's order.
func weather_choices() -> PackedStringArray:
	var out := PackedStringArray(["auto"])
	if weather != null:
		out.append_array(weather.order)
	return out


## True on a co-op guest: the host's weather and clock apply, shown greyed.
func _testing_locked() -> bool:
	return weather != null and weather.mirror


func _rebuild_testing() -> void:
	var page := _pages[TESTING_TAB]
	if (_rows[TESTING_TAB] as Array).is_empty():
		var w := _row_button("")
		w.set_meta("step", func(d: int) -> void: _step_weather(d))
		w.pressed.connect(func() -> void: _step_weather(1))
		var h := _row_button("")
		h.set_meta("step", func(d: int) -> void: _step_hour(d))
		h.pressed.connect(func() -> void: _step_hour(1))
		var m := _row_button("")
		m.set_meta("step", func(d: int) -> void: _step_day_minutes(d))
		m.pressed.connect(func() -> void: _step_day_minutes(1))
		for b in [w, h, m]:
			page.add_child(b)
		var note := Label.new()
		note.name = "Note"
		note.theme_type_variation = MenuTheme.NOTE
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.add_child(note)
		_rows[TESTING_TAB] = [w, h, m]
	var rows_now: Array = _rows[TESTING_TAB]
	var locked := _testing_locked()
	var arrows := func(text: String) -> String: return text if locked else "<  %s  >" % text
	var weather_text := "(not running)"
	if weather != null:
		weather_text = weather.next_state.capitalize() if weather.pinned else "Auto (%s)" % weather.state.capitalize()
	_set_text(rows_now[0], "Weather: %s" % arrows.call(weather_text))
	var hour_text := "(not running)"
	var minutes_text := "(not running)"
	if day_night != null:
		hour_text = "Fixed %s" % day_night.clock_text() if not day_night.running else "Auto (%s)" % day_night.clock_text()
		minutes_text = "%d min a day" % int(day_night.day_minutes())
	_set_text(rows_now[1], "Time: %s" % arrows.call(hour_text))
	_set_text(rows_now[2], "Day length: %s" % arrows.call(minutes_text))
	for b: Button in rows_now:
		b.disabled = locked
	(page.get_node("Note") as Label).text = "The host's weather and time apply to everyone." if locked else "For testing: a picked weather holds until Auto; a fixed hour stops the clock. Turn Tester options off in Settings to hide this tab."


func _step_weather(delta: int) -> void:
	if weather == null or _testing_locked():
		return
	var choices := weather_choices()
	var current := weather.next_state if weather.pinned else "auto"
	var pick := choices[posmod(maxi(choices.find(current), 0) + delta, choices.size())]
	if pick == "auto":
		weather.release()
	else:
		weather.hold(pick)
	_rebuild_testing()
	_highlight()


func _step_hour(delta: int) -> void:
	if day_night == null or _testing_locked():
		return
	var current := -1.0 if day_night.running else day_night.hour
	var i := 0
	for k in range(TEST_HOURS.size()):
		if is_equal_approx(TEST_HOURS[k], current):
			i = k
	var pick := TEST_HOURS[posmod(i + delta, TEST_HOURS.size())]
	if pick < 0.0:
		day_night.run()
	else:
		day_night.fix_hour(pick)
	_rebuild_testing()
	_highlight()


func _step_day_minutes(delta: int) -> void:
	if day_night == null or _testing_locked():
		return
	var i := 0
	var best := INF
	for k in range(TEST_DAY_MINUTES.size()):
		var d := absf(TEST_DAY_MINUTES[k] - day_night.day_minutes())
		if d < best:
			best = d
			i = k
	day_night.set_day_minutes(TEST_DAY_MINUTES[clampi(i + delta, 0, TEST_DAY_MINUTES.size() - 1)])
	_rebuild_testing()
	_highlight()


## Tester options turned off: the weather table and the clock run again.
func _release_testing() -> void:
	if _testing_locked():
		return
	if weather != null:
		weather.release()
	if day_night != null:
		day_night.run()


# --- Packs tab (add-pack-loader) ---

func _build_packs_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "Packs"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 8)
	_packs_scroll = ScrollContainer.new()
	_packs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(MenuTheme.scroll_frame(_packs_scroll))
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", int(MenuTheme.num(MenuTheme.theme().get_meta("data", {}), "spacing", "scroll_gutter", 12)))
	_packs_scroll.add_child(gutter)
	_packs_list = VBoxContainer.new()
	_packs_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_packs_list.add_theme_constant_override("separation", 2)
	gutter.add_child(_packs_list)
	_packs_note = Label.new()
	_packs_note.name = "Note"
	_packs_note.theme_type_variation = MenuTheme.NOTE
	_packs_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_packs_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_packs_note)
	_pages_root.add_child(page)
	return page


## One row per discovered pack: `[x] Name  type  version`, with the loader's state on the
## right. Accept toggles a data-only non-map pack; on another map pack it asks once, then saves
## that map and restarts the game there; system packs and refused packs say why they cannot be
## enabled. Other changes apply at the next load.
func _rebuild_packs() -> void:
	if _packs_list == null:
		return
	var keep := _selected[PACKS_TAB]
	for c in _packs_list.get_children():
		_packs_list.remove_child(c)
		c.queue_free()
	var buttons: Array[Button] = []
	var maps := 0
	for info: PackLoader.PackInfo in PackLoader.listed():
		if info.is_map():
			maps += 1
		var b := _pack_row(info)
		_packs_list.add_child(b)
		buttons.append(b)
	if buttons.is_empty():
		var none := _row_button("No packs found")
		none.pressed.connect(func() -> void: _packs_note.text = "Packs go in %s" % "\n".join(PackLoader.dirs()))
		_packs_list.add_child(none)
		buttons.append(none)
	_rows[PACKS_TAB] = buttons
	_selected[PACKS_TAB] = clampi(keep, 0, buttons.size() - 1)
	var enabled_maps := 0
	for id in PackLoader.enabled_ids():
		if (PackLoader.packs[id] as PackLoader.PackInfo).is_map():
			enabled_maps += 1
	_packs_note.text = "Changes apply at the next load. The map in play is %s%s" % [
		PackLoader.active_map if PackLoader.active_map != "" else "(none)",
		"; A on another map plays it (the game restarts)." if maps > 1 else ".",
	]


func _pack_row(info: PackLoader.PackInfo) -> Button:
	var mark := "[x]" if info.enabled and info.valid and info.reason == "" else ("[ ]" if info.valid else "[!]")
	var b := _row_button("%s %s   %s %s" % [mark, info.name, info.type, info.version])
	b.add_theme_font_size_override("font_size", int(MenuTheme.num(MenuTheme.theme().get_meta("data", {}), "fonts", "body", 18)))
	b.set_meta("pack_id", info.id)
	var state := MenuTheme.key_cap(PackLoader.state_text(info))
	if info.type == "system" or not info.valid:
		state.modulate = Color(1.0, 0.7, 0.4)
	state.anchor_left = 1.0
	state.anchor_right = 1.0
	state.anchor_top = 0.5
	state.anchor_bottom = 0.5
	state.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	state.grow_vertical = Control.GROW_DIRECTION_BOTH
	state.offset_left = -12.0
	state.offset_right = -12.0
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(state)
	b.pressed.connect(_toggle_pack.bind(info.id))
	return b


func _toggle_pack(id: String) -> void:
	if not PackLoader.packs.has(id):
		return
	var info: PackLoader.PackInfo = PackLoader.packs[id]
	if not info.is_map():
		_map_confirm = ""
	if info.type == "system":
		_packs_note.text = "%s runs code; system packs are not supported yet." % info.name
	elif not info.valid:
		_packs_note.text = "%s cannot be enabled: %s" % [info.name, info.reason]
	elif info.is_map():
		_choose_map(info)
		return
	elif Session.is_online():
		_packs_note.text = "Packs cannot change during a co-op session."
	else:
		var on := not info.enabled
		PackLoader.set_enabled(id, on)
		_packs_note.text = "%s %s; applies at the next load." % [info.name, "enabled" if on else "disabled"]
	_rebuild_packs()
	_highlight()


## A map pack row: the map in play says so; another asks for a second press, then is saved as
## the map (`[map] pack` in settings.cfg) and the game restarts on it. Not during co-op.
func _choose_map(info: PackLoader.PackInfo) -> void:
	if info.id == PackLoader.active_map:
		_map_confirm = ""
		_packs_note.text = "%s is the map in play." % info.name
	elif Session.is_online():
		_map_confirm = ""
		_packs_note.text = "The map cannot change during a co-op session."
	elif _map_confirm != info.id:
		_map_confirm = info.id
		_packs_note.text = "Press A again to play %s: the game restarts there." % info.name
	else:
		_map_confirm = ""
		Settings.map_pack = info.id
		Settings.save_settings()
		_packs_note.text = "Restarting on %s..." % info.name
		restart_game.call()
	_highlight()


## Restarts the game with the same command line, less any --pack= (the saved map wins).
static func restart_with_saved_map() -> void:
	var args := OS.get_cmdline_args()
	var user := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--pack="):
			user.append(a)
	if not user.is_empty():
		args.append("--")
		args.append_array(user)
	OS.set_restart_on_exit(true, args)
	Engine.get_main_loop().quit()


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
	_map_confirm = ""
	if overview_map != null and overview_map.visible:
		overview_map.close()
	capture()
	MenuTheme.refresh_accent()
	visible = true
	_selected = PackedInt32Array()
	_selected.resize(TABS.size())
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
