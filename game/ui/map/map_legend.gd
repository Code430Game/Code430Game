class_name MapLegend
extends PanelContainer
## The full map's legend and places list (add-map-legend). Two levels, plain like a search
## result list rather than a cycle through markers:
##   kinds  - one row per kind of place the pack has: its icon, its name, how many;
##   places - one kind's places, nearest first: icon, street address, name, distance.
## Up / Down (D-pad, arrows) move the selection, A (or a click) opens a kind or picks a place,
## B (or the back row) goes back a level; B on the kinds closes the map (`back_out`). Picking a
## place emits `place_chosen`; the map centres on it and highlights it. Looks come from
## MenuTheme; kinds, names and icons from PlaceIcons.

signal place_chosen(place: Services.Place)
signal back_out

enum Level { KINDS, PLACES }

const WIDTH_PX := 500.0
const ICON_PX := 30.0

var places: Array = []  # Services.Place
## Where "nearest first" measures from (the player); null keeps the data's order.
var origin: Node3D
## The tallest the panel may grow (the map sets it from its view); longer lists scroll.
var max_height: float = 640.0
var level: Level = Level.KINDS
var kind: String = ""  # the kind open at the PLACES level
var selected: int = 0

var _title: Label
var _note: Label
var _rows_box: VBoxContainer
var _scroll: ScrollContainer
var _rows: Array[Control] = []
var _entries: Array = []  # what each row stands for: a kind (String) or a Services.Place


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH_PX, 0.0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_title = Label.new()
	_title.theme_type_variation = MenuTheme.HEADING
	col.add_child(_title)
	_note = Label.new()
	_note.theme_type_variation = MenuTheme.NOTE
	col.add_child(_note)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 2)
	_scroll.add_child(_rows_box)
	col.add_child(_scroll)
	rebuild()


## The kinds of place to list, in PlaceIcons' order, then any unknown kinds by id.
func kinds_present() -> PackedStringArray:
	var have := {}
	for p: Services.Place in places:
		have[p.kind] = true
	var out := PackedStringArray()
	for k in PlaceIcons.kinds():
		if have.has(k):
			out.append(k)
	var extra: Array = []
	for k: String in have:
		if not out.has(k):
			extra.append(k)
	extra.sort()
	for k: String in extra:
		out.append(k)
	return out


## The places of `of_kind`, nearest `origin` first (ties by name, then id).
func places_of(of_kind: String) -> Array:
	var out: Array = places.filter(func(p: Services.Place) -> bool: return p.kind == of_kind)
	var from := origin.global_position if origin != null and origin.is_inside_tree() else Vector3.INF
	out.sort_custom(func(a: Services.Place, b: Services.Place) -> bool:
		if from != Vector3.INF:
			var da := _flat_distance(a.at, from)
			var db := _flat_distance(b.at, from)
			if absf(da - db) > 0.01:
				return da < db
		if a.name != b.name:
			return a.name < b.name
		return a.id < b.id)
	return out


## What the rows stand for right now: kinds (String) or places (Services.Place).
func entries() -> Array:
	return _entries


## Back to the kinds list with nothing selected beyond the first row.
func reset() -> void:
	level = Level.KINDS
	kind = ""
	selected = 0
	rebuild()


## Moves the selection by `step` rows, staying inside the list.
func move(step: int) -> void:
	if _entries.is_empty():
		return
	select(clampi(selected + step, 0, _entries.size() - 1))


## Selects row `i` and scrolls it into view.
func select(i: int) -> void:
	selected = clampi(i, 0, maxi(_entries.size() - 1, 0))
	for r in range(_rows.size()):
		MenuTheme.set_selected(_rows[r], r == selected)
	if selected < _rows.size() and _rows[selected].is_inside_tree():
		_scroll.ensure_control_visible(_rows[selected])


## A on the selected row: opens a kind, or picks a place.
func accept() -> void:
	if _entries.is_empty():
		return
	var e: Variant = _entries[selected]
	if e is String:
		level = Level.PLACES
		kind = e
		selected = 0
		rebuild()
	elif e is Services.Place:
		place_chosen.emit(e)


## B: from a kind's places back to the kinds (that kind selected); from the kinds, `back_out`.
func back() -> void:
	if level == Level.PLACES:
		var was := kind
		level = Level.KINDS
		kind = ""
		rebuild()
		select(maxi(kinds_present().find(was), 0))
	else:
		back_out.emit()


## Rebuilds the rows for the current level.
func rebuild() -> void:
	if _rows_box == null:
		return
	for r in _rows:
		_rows_box.remove_child(r)
		r.free()  # detached rows: free now, nothing left outside the tree
	_rows.clear()
	_entries.clear()
	if level == Level.KINDS:
		_title.text = "Places"
		_note.text = "Pick a kind to list its places" if not places.is_empty() else "No places in this map"
		for k in kinds_present():
			var n := places.filter(func(p: Services.Place) -> bool: return p.kind == k).size()
			_add_row(k, PlaceIcons.label(k), "", str(n), k)
	else:
		_title.text = PlaceIcons.label(kind)
		_note.text = "Nearest first.  B back to all places"
		var from := origin.global_position if origin != null and origin.is_inside_tree() else Vector3.INF
		for p: Services.Place in places_of(kind):
			var main := p.address if p.address != "" else "No street address"
			var sub := p.name if p.name != "" else PlaceIcons.label(p.kind)
			if p.title != "":  # named by title ("Kent St Parking"): its kind's note underneath
				main = p.title
				sub = PlaceIcons.note(p.kind)
			var dist := distance_text(_flat_distance(p.at, from)) if from != Vector3.INF else ""
			_add_row(p.kind, main, sub, dist, p, p.title == "")
	fit_height()
	fit_height.call_deferred()  # again once wrapped names know their width
	select(selected)


## Sizes the list to its rows, up to `max_height` for the whole panel; past that it scrolls.
func fit_height() -> void:
	if not is_instance_valid(_scroll):
		return
	_scroll.custom_minimum_size.y = 0.0
	var rows_h := _rows_box.get_combined_minimum_size().y
	var frame_h := get_combined_minimum_size().y  # title, note and padding around an empty list
	_scroll.custom_minimum_size.y = minf(rows_h, maxf(max_height - frame_h, 0.0))
	reset_size()


## "350 m" (to the nearest 10 m) under a kilometre, "1.2 km" above.
static func distance_text(metres: float) -> String:
	if metres < 1000.0:
		return "%d m" % int(roundf(metres / 10.0) * 10.0)
	return "%.1f km" % (metres / 1000.0)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _add_row(icon_kind: String, main: String, sub: String, right: String, entry: Variant, wrap_sub: bool = true) -> void:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	MenuTheme.set_selected(row, false)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var icon := TextureRect.new()
	icon.texture = PlaceIcons.texture(icon_kind)
	icon.modulate = PlaceIcons.color(icon_kind).lightened(0.25)
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(texts)
	var main_label := Label.new()
	main_label.text = main
	main_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	main_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(main_label)
	if sub != "":
		var sub_label := Label.new()
		sub_label.text = sub
		sub_label.theme_type_variation = MenuTheme.NOTE
		if wrap_sub:
			sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long names wrap rather than cut
		else:
			sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # a short note: one line
		sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(sub_label)
	if right != "":
		var right_label := Label.new()
		right_label.text = right
		right_label.theme_type_variation = MenuTheme.NOTE
		right_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		right_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(right_label)
	var index := _rows.size()
	row.gui_input.connect(func(event: InputEvent) -> void: _on_row_input(index, event))
	_rows_box.add_child(row)
	_rows.append(row)
	_entries.append(entry)


func _on_row_input(index: int, event: InputEvent) -> void:
	if event is InputEventMouseMotion and index != selected:
		select(index)
	elif event is InputEventMouseButton and event.pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			select(index)
			accept()
			accept_event()
		elif (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			back()
			accept_event()
