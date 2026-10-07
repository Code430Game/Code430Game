class_name MenuTheme
extends RefCounted
## One look for every menu (update-menu-design): a Godot Theme built in code from
## `menu_theme.json`, shared by the pause menu, the character creator, the report form and the
## full map. Panels are near-opaque, bordered and rounded with a soft shadow and padding inside;
## list rows are inset from the panel's edge and the selected one is filled with the tone's
## accent with a bar on its left (no text marker). Tabs sit on a strip, hints in a footer as key
## caps. Menus pick the look by type variation (ROW, ROW_SELECTED, TAB, KEY_CAP ...); the accent
## boxes are shared, so recolouring them on a tone change recolours every menu at once.

const PATH := "res://ui/menu_theme.json"

## Type variations. Rows come as a Button, a PanelContainer (a row of several labels) or a Label.
const ROW := "MenuRow"
const ROW_SELECTED := "MenuRowSelected"
const ROW_PANEL := "MenuRowPanel"
const ROW_PANEL_SELECTED := "MenuRowPanelSelected"
const ROW_PANEL_COMPACT := "MenuRowPanelCompact"
const ROW_PANEL_COMPACT_SELECTED := "MenuRowPanelCompactSelected"
const ROW_LABEL := "MenuRowLabel"
const ROW_LABEL_SELECTED := "MenuRowLabelSelected"
const ROW_LABEL_COMPACT := "MenuRowLabelCompact"
const ROW_LABEL_COMPACT_SELECTED := "MenuRowLabelCompactSelected"
const TAB := "MenuTab"
const STRIP := "MenuStrip"
const FOOTER := "MenuFooter"
const KEY_CAP := "KeyCap"
const HINT := "MenuHint"
const NOTE := "MenuNote"
const HEADING := "MenuHeading"
const TITLE := "MenuTitle"
const TOOLTIP := "MenuTooltip"

static var _theme: Theme
static var _accent_mode: String = ""


## The shared theme, built on first use; its accent follows the active tone.
static func theme() -> Theme:
	if _theme == null:
		_theme = build(load_data())
		_accent_mode = ""
	if _accent_mode != ContentMode.current:
		refresh_accent()
	return _theme


## Recolours the accent parts (selected rows, the active tab, a focused field, section
## headings) with the tone's.
static func refresh_accent() -> void:
	if _theme == null:
		theme()
		return
	apply_accent(_theme, ContentMode.hud_accent())
	_accent_mode = ContentMode.current


static func load_data(path: String = PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## A colour from the data's `colors`, or `fallback`.
static func color(data: Dictionary, key: String, fallback: Color = Color.MAGENTA) -> Color:
	var hex := str((data.get("colors", {}) as Dictionary).get(key, ""))
	return Color.html(hex) if Color.html_is_valid(hex) else fallback


## A number from one of the data's groups (`spacing`, `shape`, `fonts`), or `fallback`.
static func num(data: Dictionary, group: String, key: String, fallback: float = 0.0) -> float:
	return float((data.get(group, {}) as Dictionary).get(key, fallback))


## Builds a theme from `data` (tests pass their own). The accent starts white until
## `apply_accent` paints it.
static func build(data: Dictionary) -> Theme:
	var t := Theme.new()
	t.set_meta("data", data)
	var fills: Array[StyleBoxFlat] = []  # selected rows: accent at selection_alpha, accent bar
	var solids: Array[StyleBoxFlat] = []  # the active tab: accent fill
	var borders: Array[StyleBoxFlat] = []  # a focused field: accent border
	var text := color(data, "text")
	var muted := color(data, "muted")
	var small := int(num(data, "fonts", "small", 16))
	var body := int(num(data, "fonts", "body", 18))
	t.default_font_size = body
	t.set_color("font_color", "Label", text)

	# Panels: the menu's frame, with the outer padding inside.
	var pad := num(data, "spacing", "outer_padding", 24)
	var panel := _box(color(data, "panel"), num(data, "shape", "radius", 12), Vector4(pad, pad, pad, pad))
	panel.border_color = color(data, "border")
	panel.set_border_width_all(int(num(data, "shape", "border_px", 1)))
	panel.shadow_color = color(data, "shadow")
	panel.shadow_size = int(num(data, "shape", "shadow_px", 18))
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var sp := num(data, "spacing", "strip_padding", 6)
	t.set_type_variation(STRIP, "PanelContainer")
	t.set_stylebox("panel", STRIP, _box(color(data, "strip"), num(data, "shape", "radius", 12) - 2.0, Vector4(sp, sp, sp, sp)))
	var fh := num(data, "spacing", "footer_padding_h", 16)
	var fv := num(data, "spacing", "footer_padding_v", 10)
	var footer := _box(color(data, "footer"), num(data, "shape", "row_radius", 6) + 2.0, Vector4(fh, fv, fh, fv))
	t.set_type_variation(FOOTER, "PanelContainer")
	t.set_stylebox("panel", FOOTER, footer)

	# Rows: inset text, a hover tint, and the selected fill with its bar. The left margin leaves
	# room for the bar so text doesn't move when a row is selected.
	var bar := num(data, "shape", "selection_bar_px", 4)
	var rh := num(data, "spacing", "row_padding_h", 14)
	var radius := num(data, "shape", "row_radius", 6)
	var row_font := int(num(data, "fonts", "row", 20))
	for compact: bool in [false, true]:
		var rv := num(data, "spacing", "compact_row_padding_v" if compact else "row_padding_v", 6)
		var margins := Vector4(rh + bar, rv, rh, rv)
		var plain := _box(Color.TRANSPARENT, radius, margins)
		var hover := _box(color(data, "row_hover"), radius, margins)
		var selected := _box(Color.WHITE, radius, margins)
		selected.border_width_left = int(bar)
		selected.corner_radius_top_left = int(minf(radius, bar))
		selected.corner_radius_bottom_left = int(minf(radius, bar))
		fills.append(selected)
		var row_names := [ROW_PANEL_COMPACT, ROW_PANEL_COMPACT_SELECTED, ROW_LABEL_COMPACT, ROW_LABEL_COMPACT_SELECTED] if compact else [ROW_PANEL, ROW_PANEL_SELECTED, ROW_LABEL, ROW_LABEL_SELECTED]
		t.set_type_variation(row_names[0], "PanelContainer")
		t.set_stylebox("panel", row_names[0], plain)
		t.set_type_variation(row_names[1], "PanelContainer")
		t.set_stylebox("panel", row_names[1], selected)
		t.set_type_variation(row_names[2], "Label")
		t.set_stylebox("normal", row_names[2], plain)
		t.set_type_variation(row_names[3], "Label")
		t.set_stylebox("normal", row_names[3], selected)
		t.set_color("font_color", row_names[3], color(data, "selected_text"))
		if not compact:
			for type: String in ["Button", ROW]:
				t.set_stylebox("normal", type, plain)
				t.set_stylebox("hover", type, hover)
				t.set_stylebox("pressed", type, hover)
				t.set_stylebox("hover_pressed", type, hover)
				t.set_stylebox("disabled", type, plain)
				t.set_stylebox("focus", type, StyleBoxEmpty.new())
				t.set_font_size("font_size", type, row_font)
				for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
					t.set_color(c, type, text)
			t.set_type_variation(ROW, "Button")
			t.set_type_variation(ROW_SELECTED, "Button")
			for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				t.set_stylebox(s, ROW_SELECTED, selected)
			t.set_stylebox("focus", ROW_SELECTED, StyleBoxEmpty.new())
			for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
				t.set_color(c, ROW_SELECTED, color(data, "selected_text"))

	# Tabs: outlined chips on the strip, the active one filled with the accent.
	var th := num(data, "spacing", "tab_padding_h", 16)
	var tv := num(data, "spacing", "tab_padding_v", 6)
	var tab_margins := Vector4(th, tv, th, tv)
	var tab := _box(color(data, "tab"), radius, tab_margins)
	var tab_hover := _box(color(data, "tab_hover"), radius, tab_margins)
	var tab_active := _box(Color.WHITE, radius, tab_margins)
	solids.append(tab_active)
	t.set_type_variation(TAB, "Button")
	t.set_stylebox("normal", TAB, tab)
	t.set_stylebox("hover", TAB, tab_hover)
	t.set_stylebox("pressed", TAB, tab_active)
	t.set_stylebox("hover_pressed", TAB, tab_active)
	t.set_stylebox("focus", TAB, StyleBoxEmpty.new())
	t.set_font_size("font_size", TAB, int(num(data, "fonts", "tab", 18)))
	t.set_color("font_color", TAB, muted)
	t.set_color("font_hover_color", TAB, text)
	t.set_color("font_pressed_color", TAB, color(data, "tab_active_text"))
	t.set_color("font_hover_pressed_color", TAB, color(data, "tab_active_text"))

	# Text styles.
	var kh := num(data, "spacing", "key_cap_padding_h", 7)
	var kv := num(data, "spacing", "key_cap_padding_v", 2)
	var cap := _box(color(data, "key_cap"), num(data, "shape", "key_cap_radius", 5), Vector4(kh, kv, kh, kv))
	cap.border_color = color(data, "key_cap_border")
	cap.set_border_width_all(1)
	cap.border_width_bottom = 2  # a key's lower lip
	t.set_type_variation(KEY_CAP, "Label")
	t.set_stylebox("normal", KEY_CAP, cap)
	t.set_font_size("font_size", KEY_CAP, small)
	t.set_color("font_color", KEY_CAP, text)
	t.set_type_variation(HINT, "Label")
	t.set_font_size("font_size", HINT, small)
	t.set_color("font_color", HINT, muted)
	var note := StyleBoxEmpty.new()  # inset like row text, so notes line up with the rows above
	note.content_margin_left = rh + bar
	note.content_margin_right = rh
	t.set_type_variation(NOTE, "Label")
	t.set_stylebox("normal", NOTE, note)
	t.set_font_size("font_size", NOTE, small)
	t.set_color("font_color", NOTE, muted)
	var heading := StyleBoxEmpty.new()
	heading.content_margin_top = num(data, "spacing", "section_gap", 14)
	heading.content_margin_left = rh + bar
	heading.content_margin_bottom = 2.0
	t.set_type_variation(HEADING, "Label")
	t.set_stylebox("normal", HEADING, heading)
	t.set_font_size("font_size", HEADING, int(num(data, "fonts", "heading", 18)))
	t.set_color("font_color", HEADING, text)  # painted with the accent by apply_accent
	t.set_type_variation(TITLE, "Label")
	t.set_font_size("font_size", TITLE, int(num(data, "fonts", "title", 28)))
	t.set_color("font_color", TITLE, text)
	var tip := _box(color(data, "panel"), radius, Vector4(10, 4, 10, 4))
	tip.border_color = color(data, "border")
	tip.set_border_width_all(1)
	t.set_type_variation(TOOLTIP, "Label")
	t.set_stylebox("normal", TOOLTIP, tip)
	t.set_color("font_color", TOOLTIP, text)

	# Fields: dark wells with a border, the accent border while typing.
	for type: String in ["LineEdit", "TextEdit"]:
		var field := _box(color(data, "field"), radius, Vector4(10, 6, 10, 6))
		field.border_color = color(data, "border")
		field.set_border_width_all(1)
		var focus := field.duplicate() as StyleBoxFlat
		focus.set_border_width_all(2)
		borders.append(focus)
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("read_only", type, field)
		t.set_color("font_color", type, text)
		t.set_color("font_placeholder_color", type, muted)
		t.set_font_size("font_size", type, body)

	# Thin scrollbars.
	var thin := num(data, "shape", "scrollbar_px", 4)
	var track := StyleBoxEmpty.new()
	track.content_margin_left = thin * 0.5
	track.content_margin_right = thin * 0.5
	var grab := _box(color(data, "grabber"), thin, Vector4(thin * 0.5, thin, thin * 0.5, thin))
	var grab_hover := _box(color(data, "grabber_hover"), thin, Vector4(thin * 0.5, thin, thin * 0.5, thin))
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hover)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hover)

	t.set_meta("accent_fills", fills)
	t.set_meta("accent_solids", solids)
	t.set_meta("accent_borders", borders)
	apply_accent(t, Color.WHITE)
	return t


## Paints the theme's accent boxes with `accent`.
static func apply_accent(t: Theme, accent: Color) -> void:
	var data: Dictionary = t.get_meta("data", {})
	var alpha := num(data, "shape", "selection_alpha", 0.24)
	for box: StyleBoxFlat in t.get_meta("accent_fills", []):
		box.bg_color = Color(accent, alpha)
		box.border_color = accent
	for box: StyleBoxFlat in t.get_meta("accent_solids", []):
		box.bg_color = accent
	for box: StyleBoxFlat in t.get_meta("accent_borders", []):
		box.border_color = accent
	t.set_color("font_color", HEADING, accent)  # section headings carry the tone too


## Marks a row selected or not: Buttons, PanelContainers and Labels each have their pair.
static func set_selected(row: Control, selected: bool, compact: bool = false) -> void:
	if row is Button:
		row.theme_type_variation = ROW_SELECTED if selected else ROW
	elif row is PanelContainer:
		if compact:
			row.theme_type_variation = ROW_PANEL_COMPACT_SELECTED if selected else ROW_PANEL_COMPACT
		else:
			row.theme_type_variation = ROW_PANEL_SELECTED if selected else ROW_PANEL
	elif row is Label:
		if compact:
			row.theme_type_variation = ROW_LABEL_COMPACT_SELECTED if selected else ROW_LABEL_COMPACT
		else:
			row.theme_type_variation = ROW_LABEL_SELECTED if selected else ROW_LABEL


## A key cap label such as `[LB]`.
static func key_cap(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = KEY_CAP
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Fills `box` with hints: each pair is [key, what it does], drawn as a key cap and muted text.
static func hint_bar(box: HBoxContainer, pairs: Array) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.free()  # plain labels, detached: free now so nothing is left outside the tree
	var data: Dictionary = theme().get_meta("data", {})
	box.add_theme_constant_override("separation", int(num(data, "spacing", "hint_gap", 18)))
	for pair: Array in pairs:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		item.add_child(key_cap(str(pair[0])))
		var what := Label.new()
		what.text = str(pair[1])
		what.theme_type_variation = HINT
		what.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item.add_child(what)
		box.add_child(item)


## The hints of `box` as plain text, "LB / RB tabs  A select" (tests, logs).
static func hint_text(box: HBoxContainer) -> String:
	var parts := PackedStringArray()
	for item in box.get_children():
		var bits := PackedStringArray()
		for l in item.get_children():
			if l is Label:
				bits.append((l as Label).text)
		parts.append(" ".join(bits))
	return "  ".join(parts)


## Puts `scroll` in a frame with soft fades at its top and bottom edges, shown while there is
## more to scroll that way. Returns the frame to add in the scroll's place.
static func scroll_frame(scroll: ScrollContainer) -> Control:
	var data: Dictionary = theme().get_meta("data", {})
	var frame := Control.new()
	frame.name = "ScrollFrame"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.clip_contents = true
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(scroll)
	var fade := num(data, "spacing", "fade_px", 22)
	var base := color(data, "panel")
	var fades: Array[TextureRect] = []
	for top: bool in [true, false]:
		var g := Gradient.new()
		g.set_color(0, Color(base, base.a if top else 0.0))
		g.set_color(1, Color(base, 0.0 if top else base.a))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill_from = Vector2(0, 0)
		tex.fill_to = Vector2(0, 1)
		tex.width = 4
		tex.height = 32
		var r := TextureRect.new()
		r.name = "FadeTop" if top else "FadeBottom"
		r.texture = tex
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			r.offset_bottom = fade
		else:
			r.offset_top = -fade
		r.visible = false
		frame.add_child(r)
		fades.append(r)
	var update := func() -> void:
		var bar := scroll.get_v_scroll_bar()
		var more := bar.max_value - bar.page > 1.0
		fades[0].visible = more and bar.value > 1.0
		fades[1].visible = more and bar.value < bar.max_value - bar.page - 1.0
	scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: update.call())
	scroll.get_v_scroll_bar().changed.connect(update)
	return frame


## WCAG contrast ratio of two colours (1 to 21), for the readability checks.
static func contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance() + 0.05
	var lb := b.srgb_to_linear().get_luminance() + 0.05
	return maxf(la, lb) / minf(la, lb)


static func _box(bg: Color, radius: float, margins: Vector4) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(int(radius))
	b.content_margin_left = margins.x
	b.content_margin_top = margins.y
	b.content_margin_right = margins.z
	b.content_margin_bottom = margins.w
	b.anti_aliasing = true
	return b
