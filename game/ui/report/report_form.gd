class_name ReportForm
extends CanvasLayer
## "Report a problem": screenshot, area and severity, what happened, whether to include this
## install's reporter id, a review page listing everything that will be sent, and the queue. The
## title is generated from the area, severity and place.
##
## Opened from the pause menu (any input device) or with F8, while the tree is paused. Handles its
## own navigation in _input like the pause menu: up/down move, left/right change a choice, A
## activates or starts typing (the Deck shows its on-screen keyboard), B leaves a page, then the
## form. Typing ends with B or Menu on a controller, or Enter (Shift+Enter is a new line) or Escape
## on a keyboard. The D-pad and A are left alone: the Deck's on-screen keyboard is driven with them,
## and the game sees those presses too. Sending goes through `sender` (RelayClient) when there is one; the
## report is always saved first.

signal closed

enum Page { MAIN, REVIEW, QUEUE }
const ROWS := ["shot", "area", "severity", "description", "reporter", "review", "send", "queue", "cancel"]
const THUMB_SIZE := Vector2(224, 140)
const FONT := 17

var store: ReportStore
## Sends saved reports: `send(id)` and `send_due()`, signal `report_state_changed(id, state)`. Optional.
var sender: Object = null
## "owner/name" for the browser hand-off; empty hides it.
var repo: String = ""

var _page: int = Page.MAIN
var _selected: int = 0
var _screenshot: Image
var _diagnostics: Dictionary = {}
var _log_tail: Array = []
var _include_shot: bool = true
var _area: int = 0
var _severity: int = 1
var _sent_id: String = ""
var _include_reporter: bool = false
var _reporter_id: String = ""
var _queue_selected: int = 0
var _queue_action: int = 0

var _panel: PanelContainer
var _main: VBoxContainer
var _thumb: TextureRect
var _labels: Dictionary = {}  # row -> Label (caption and value)
var _title: Label
var _description: TextEdit
var _status: Label
var _review: ScrollContainer
var _review_text: Label
var _queue: VBoxContainer
var _queue_list: Label
var _queue_action_label: Label


func _ready() -> void:
	layer = 62
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## Opens the form for a screenshot and the diagnostics captured with it.
func open(screenshot: Image, diagnostics: Dictionary, log_tail: Array) -> void:
	_screenshot = screenshot
	_diagnostics = diagnostics
	_log_tail = log_tail
	_include_shot = screenshot != null
	_area = 0
	_severity = 1
	_sent_id = ""
	_include_reporter = false
	_reporter_id = ReportStore.reporter_id()
	_description.text = ""
	_status.text = ""
	_thumb.texture = ImageTexture.create_from_image(screenshot) if screenshot != null else null
	_show_page(Page.MAIN)
	_selected = 0
	visible = true
	get_tree().paused = true
	_refresh()
	if sender != null and store != null:
		sender.send_due()


## Closes the form; whoever opened it decides what comes next.
func close() -> void:
	_release_text()
	visible = false
	closed.emit()


## The fields as the report will carry them.
func fields() -> Dictionary:
	return {
		"area": ReportStore.AREAS[_area][0], "severity": ReportStore.SEVERITIES[_severity][0],
		"description": _description.text, "reporter_id": _reporter_id if _include_reporter else "",
	}


## The report as it would be sent now (for the review page and tests).
func preview() -> Dictionary:
	var include := _include_shot and _screenshot != null
	return ReportStore.build(fields(), _diagnostics, _log_tail, include)


## Saves the report, then hands it to the sender. Returns the report id.
func send() -> String:
	if _sent_id != "":
		return _sent_id
	var report := preview()
	_sent_id = store.save(report, _screenshot if report["has_screenshot"] else null)
	if sender != null:
		_status.text = "Saved. Sending..."
		sender.send(_sent_id)
	elif repo != "" and _can_open_browser():
		_status.text = "Saved. No report service is set up yet: open Saved reports to file it in the browser."
	else:
		_status.text = "Saved on this machine as %s. It will be sent once reporting is set up." % _sent_id
	_refresh()
	return _sent_id


## Called by the sender as a report's state changes.
func on_report_state(id: String, state: Dictionary) -> void:
	if id == _sent_id:
		match str(state.get("state", "")):
			"sent":
				_status.text = "Filed: %s" % state.get("issue_url", "")
			"failed", "queued":
				_status.text = "Saved; not sent yet (%s). It will retry." % state.get("error", "offline")
	_refresh()
	if _page == Page.QUEUE:
		_refresh_queue()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _text_focused():
		if _leaves_text(event):
			_release_text()
			get_viewport().set_input_as_handled()
		return  # typing: everything else goes to the field
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _page == Page.MAIN:
			close()
		else:
			_show_page(Page.MAIN)
	elif _page == Page.REVIEW:
		if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
			_review.scroll_vertical += 120 * (1 if event.is_action_pressed("ui_down") else -1)
		elif not event.is_pressed():
			return
	elif _page == Page.QUEUE:
		_queue_input(event)
	elif event.is_action_pressed("ui_down"):
		_selected = (_selected + 1) % ROWS.size()
		_refresh()
	elif event.is_action_pressed("ui_up"):
		_selected = (_selected - 1 + ROWS.size()) % ROWS.size()
		_refresh()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_change(ROWS[_selected], 1 if event.is_action_pressed("ui_right") else -1)
	elif event.is_action_pressed("ui_accept"):
		_activate(ROWS[_selected])
	elif not event.is_pressed():
		return
	get_viewport().set_input_as_handled()


func _queue_input(event: InputEvent) -> void:
	var rows := store.list()
	var actions := _queue_actions()
	if event.is_action_pressed("ui_down") and not rows.is_empty():
		_queue_selected = (_queue_selected + 1) % rows.size()
	elif event.is_action_pressed("ui_up") and not rows.is_empty():
		_queue_selected = (_queue_selected - 1 + rows.size()) % rows.size()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_queue_action = posmod(_queue_action + (1 if event.is_action_pressed("ui_right") else -1), actions.size())
	elif event.is_action_pressed("ui_accept") and not rows.is_empty():
		var id: String = rows[clampi(_queue_selected, 0, rows.size() - 1)]["id"]
		match actions[_queue_action]:
			"Send now":
				if sender != null:
					sender.send(id)
			"Open in browser":
				OS.shell_open(ReportStore.handoff_url(repo, store.load_report(id)))
				OS.shell_open(store.folder_path(id))
			"Delete":
				store.delete(id)
				_queue_selected = maxi(0, _queue_selected - 1)
	_refresh_queue()


func _queue_actions() -> Array:
	var actions := []
	if sender != null:
		actions.append("Send now")
	if repo != "" and _can_open_browser():
		actions.append("Open in browser")
	actions.append("Delete")
	return actions


func _change(row: String, delta: int) -> void:
	match row:
		"shot":
			_include_shot = _screenshot != null and not _include_shot
		"area":
			_area = posmod(_area + delta, ReportStore.AREAS.size())
		"severity":
			_severity = posmod(_severity + delta, ReportStore.SEVERITIES.size())
		"reporter":
			_include_reporter = not _include_reporter
	_refresh()


func _activate(row: String) -> void:
	match row:
		"shot", "area", "severity", "reporter":
			_change(row, 1)
		"description":
			_description.grab_focus()
		"review":
			_review_text.text = _review_body()
			_show_page(Page.REVIEW)
		"send":
			send()
		"queue":
			_queue_selected = 0
			_queue_action = 0
			_show_page(Page.QUEUE)
			_refresh_queue()
		"cancel":
			close()


func _review_body() -> String:
	var report := preview()
	var lines := PackedStringArray([
		"Everything below is sent with the report%s." % (", plus the screenshot" if report["has_screenshot"] else ""),
		"Reports go to the project's GitHub issues: visible to its collaborators now, and to everyone once the project is public.",
		"",
	])
	lines.append(JSON.stringify(report, "  ", false))
	return "\n".join(lines)


func _refresh() -> void:
	var values := {
		"shot": ("<  included  >" if _include_shot else "<  left out  >") if _screenshot != null else "none captured",
		"area": "<  %s  >" % ReportStore.AREAS[_area][1],
		"severity": "<  %s  >" % ReportStore.SEVERITIES[_severity][1],
		"description": "", "reporter": ("<  included: %s  >" % _reporter_id) if _include_reporter else "<  not included  >",
		"review": "", "send": _send_state(), "queue": "%d saved" % (store.list().size() if store != null else 0), "cancel": "",
	}
	var captions := {
		"shot": "Screenshot", "area": "Area", "severity": "Severity",
		"description": "What happened (A to type, B when done)", "reporter": "Reporter id", "review": "Review what will be sent",
		"send": "Send report", "queue": "Saved reports", "cancel": "Cancel",
	}
	for i in range(ROWS.size()):
		var row: String = ROWS[i]
		var label: Label = _labels[row]
		var value: String = values[row]
		label.text = ("> " if i == _selected else "   ") + captions[row] + ("    " + value if value != "" else "")
	_thumb.modulate = Color(1, 1, 1, 1.0 if _include_shot else 0.25)
	_title.text = ReportStore.auto_title(ReportStore.AREAS[_area][0], ReportStore.SEVERITIES[_severity][0], _diagnostics.get("place", {}))


## "sent" once the relay confirmed, "saved" while it waits, nothing before Send.
func _send_state() -> String:
	if _sent_id == "" or store == null:
		return ""
	return "sent" if store.state_of(_sent_id).get("state", "") == "sent" else "saved"


func _refresh_queue() -> void:
	if store == null:
		return
	var rows := store.list()
	var lines := PackedStringArray()
	if rows.is_empty():
		lines.append("No saved reports.")
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		lines.append("%s[%s] %s" % ["> " if i == _queue_selected else "   ", r["state"], r["title"]])
	_queue_list.text = "\n".join(lines)
	var actions := _queue_actions()
	_queue_action = clampi(_queue_action, 0, actions.size() - 1)
	_queue_action_label.text = "A:  <  %s  >      B back" % actions[_queue_action]


func _show_page(page: int) -> void:
	_page = page
	_main.visible = page == Page.MAIN
	_review.visible = page == Page.REVIEW
	_queue.visible = page == Page.QUEUE


func _text_focused() -> bool:
	return _description.has_focus()


## Typing ends with B or Menu, or Enter (not Shift+Enter) or Escape. The D-pad and A drive the
## Deck's on-screen keyboard, which the game also hears, so they must not end typing.
func _leaves_text(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).button_index in [JOY_BUTTON_B, JOY_BUTTON_START]
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.keycode == KEY_ESCAPE or (k.keycode in [KEY_ENTER, KEY_KP_ENTER] and not k.shift_pressed)
	return false


func _release_text() -> void:
	if _description.has_focus():
		_description.release_focus()
	_refresh()


func _can_open_browser() -> bool:
	return OS.has_feature("pc") and not Settings.is_steam_deck


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(720, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	_panel.add_child(outer)
	var heading := Label.new()
	heading.text = "Report a problem"
	heading.add_theme_font_size_override("font_size", 22)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(heading)
	var hint := Label.new()
	hint.text = "Up/down move    left/right change    A select or type    B done typing, then back"
	hint.add_theme_font_size_override("font_size", 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(hint)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_title)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 2)
	outer.add_child(_main)
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = THUMB_SIZE
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_main.add_child(_thumb)
	for row in ROWS:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", FONT)
		_labels[row] = label
		_main.add_child(label)
		match row:
			"description":
				_description = TextEdit.new()
				_description.custom_minimum_size = Vector2(0, 96)
				_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
				_description.add_theme_font_size_override("font_size", 16)
				_description.placeholder_text = "What did you see, and what did you expect?"
				_description.focus_mode = Control.FOCUS_CLICK
				_main.add_child(_description)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)

	_review = ScrollContainer.new()
	_review.custom_minimum_size = Vector2(0, 600)
	_review_text = Label.new()
	_review_text.add_theme_font_size_override("font_size", 13)
	_review_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_review.add_child(_review_text)
	outer.add_child(_review)

	_queue = VBoxContainer.new()
	_queue.custom_minimum_size = Vector2(0, 400)
	_queue_list = Label.new()
	_queue_list.add_theme_font_size_override("font_size", 16)
	_queue_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_queue.add_child(_queue_list)
	_queue_action_label = Label.new()
	_queue_action_label.add_theme_font_size_override("font_size", FONT)
	_queue.add_child(_queue_action_label)
	outer.add_child(_queue)
	_show_page(Page.MAIN)
