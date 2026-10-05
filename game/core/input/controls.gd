class_name Controls
extends RefCounted
## The control layout as data: which actions belong to which context (on foot, driving,
## debug), what the player sees them called, and the names of buttons and keys. The bindings
## themselves are the InputMap (defaults in project.godot, the player's overrides applied by
## Settings). The conflict test, the Controls tab and the doc generator all read
## `controls.json`, so they cannot disagree.

const DATA_PATH := "res://core/input/controls.json"
## A context whose actions are live alongside every other context.
const ANY := "any"

const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Menu",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}
const PAD_AXIS_NAMES := {
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
	JOY_AXIS_LEFT_X: "left stick", JOY_AXIS_LEFT_Y: "left stick",
	JOY_AXIS_RIGHT_X: "right stick", JOY_AXIS_RIGHT_Y: "right stick",
}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "left click", MOUSE_BUTTON_RIGHT: "right click", MOUSE_BUTTON_MIDDLE: "middle click",
}

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"contexts": {}, "rows": [], "shared": []}
	return _data


## The rows for one context, in display order; `include_reserved` adds the bound-but-unused ones.
static func rows(context: String, include_reserved: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in data()["rows"]:
		if str(row["context"]) == context and (include_reserved or not bool(row.get("reserved", false))):
			out.append(row)
	return out


static func row_actions(row: Dictionary) -> PackedStringArray:
	if row.has("action"):
		return PackedStringArray([str(row["action"])])
	return PackedStringArray(row.get("actions", []))


## Every action live in `context`, reserved ones included (a later change will use them, so
## nothing else may take their buttons). Actions live everywhere count in every context.
static func actions_in(context: String) -> PackedStringArray:
	var out := PackedStringArray()
	for ctx: String in [context, ANY]:
		for row in rows(ctx, true):
			for action in row_actions(row):
				if not out.has(action):
					out.append(action)
	return out


## The contexts that conflict checks run in (the "any" context is folded into each).
static func contexts() -> PackedStringArray:
	var out := PackedStringArray()
	for ctx: String in data()["contexts"]:
		if ctx != ANY:
			out.append(ctx)
	return out


static func context_label(context: String) -> String:
	return str(data()["contexts"].get(context, context))


## True when the two actions are meant to share a button (a tap and a hold on R3).
static func may_share(a: String, b: String) -> bool:
	for pair: Array in data()["shared"]:
		if pair.has(a) and pair.has(b):
			return true
	return false


static func hold_s() -> float:
	return float(data().get("hold_s", 1.0))


## The label a player sees for `action` (its first row's), or the action name.
static func label(action: String) -> String:
	for row: Dictionary in data()["rows"]:
		if row.get("action", "") == action:
			return str(row["label"])
	return action


static func is_pad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


static func is_key_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventMouseButton


## Two events that would fire for the same press (button index, axis and direction, or key).
static func same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma := a as InputEventJoypadMotion
		var mb := b as InputEventJoypadMotion
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)
	if a is InputEventKey and b is InputEventKey:
		return _keycode(a as InputEventKey) == _keycode(b as InputEventKey)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


static func _keycode(k: InputEventKey) -> int:
	return int(k.physical_keycode) if k.physical_keycode != KEY_NONE else int(k.keycode)


## A short name for a button, axis, key or mouse button: "RB", "LT", "D-pad right", "Shift".
static func event_text(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		var i := (event as InputEventJoypadButton).button_index
		return PAD_BUTTON_NAMES.get(i, "button %d" % i)
	if event is InputEventJoypadMotion:
		var a := (event as InputEventJoypadMotion).axis
		return PAD_AXIS_NAMES.get(a, "axis %d" % a)
	if event is InputEventMouseButton:
		var m := (event as InputEventMouseButton).button_index
		return MOUSE_NAMES.get(m, "mouse %d" % m)
	if event is InputEventKey:
		var code := _keycode(event as InputEventKey)
		if code == KEY_ESCAPE:
			return "Esc"
		return OS.get_keycode_string(code as Key)
	return "?"


## What to press for `action` on a controller (`pad`) or keyboard and mouse, joined with " or ".
static func binding_text(action: String, pad: bool) -> String:
	var names := PackedStringArray()
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if (pad and is_pad_event(event)) or (not pad and is_key_event(event)):
				var text := event_text(event)
				if not names.has(text):
					names.append(text)
	return " or ".join(names)


## The text for a row: its fixed text when it has one (stick groups), else the bindings,
## with "hold" for a hold action.
static func row_text(row: Dictionary, pad: bool) -> String:
	var fixed := "pad" if pad else "key"
	if row.has(fixed):
		return str(row[fixed])
	var actions := row_actions(row)
	var text := binding_text(actions[0], pad)
	if text == "":
		return "-"
	if bool(row.get("hold", false)):
		text = "hold %s" % text
	return text


## The action in a context shared with `action` that `event` already triggers, or "" when the
## press is free for it. Shared tap/hold pairs are allowed.
static func conflict(action: String, event: InputEvent) -> String:
	for ctx in contexts():
		var live := actions_in(ctx)
		if not live.has(action):
			continue
		for other in live:
			if other == action or may_share(action, other) or not InputMap.has_action(other):
				continue
			for e in InputMap.action_get_events(other):
				if same_input(e, event):
					return other
	return ""


## A binding as plain data for the settings file (and back): which button, axis direction,
## key or mouse button.
static func event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventJoypadButton:
		return {"type": "button", "index": (event as InputEventJoypadButton).button_index}
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		return {"type": "axis", "axis": m.axis, "value": signf(m.axis_value)}
	if event is InputEventKey:
		return {"type": "key", "code": _keycode(event as InputEventKey)}
	if event is InputEventMouseButton:
		return {"type": "mouse", "index": (event as InputEventMouseButton).button_index}
	return {}


static func event_from_dict(d: Dictionary) -> InputEvent:
	match str(d.get("type", "")):
		"button":
			var b := InputEventJoypadButton.new()
			b.button_index = int(d["index"]) as JoyButton
			return b
		"axis":
			var m := InputEventJoypadMotion.new()
			m.axis = int(d["axis"]) as JoyAxis
			m.axis_value = float(d["value"])
			return m
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d["code"]) as Key
			return k
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(d["index"]) as MouseButton
			return mb
	return null


## Replaces `action`'s bindings of the event's kind (controller, or keyboard and mouse) with it.
static func replace_binding(action: String, event: InputEvent) -> void:
	var pad := is_pad_event(event)
	for e in InputMap.action_get_events(action):
		if is_pad_event(e) == pad:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, event)


## True for actions whose bindings the player may change: single actions, not stick groups.
static func rebindable(action: String) -> bool:
	for row: Dictionary in data()["rows"]:
		if row.get("action", "") == action and not bool(row.get("reserved", false)):
			return true
	return false
