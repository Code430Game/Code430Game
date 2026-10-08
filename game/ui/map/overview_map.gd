class_name OverviewMap
extends CanvasLayer
## Full-screen map (the pause-menu map). Toggled with `map_toggle` (Back alone, or M).
## Pauses the game while open. Left stick pans, right stick moves the cursor,
## triggers zoom, and the road under the cursor is highlighted and named. Its header and hover
## label use MenuTheme (update-menu-design).
##
## Places (services and garages) are drawn at screen size with PlaceIcons, and the legend on
## the right lists them (add-map-legend): Up / Down and A open a kind and pick a place, which
## centres the map on it and highlights it; B goes back a level, and closes the map from the
## kinds. A click works on the rows, a right click goes back. The title, legend and key-cap
## hints share one column on the right; the road label stays by the cursor.

signal opened
signal closed

const ZOOM_MIN := 0.15
const ZOOM_MAX := 3.0
const ZOOM_SPEED := 1.6
const PAN_SPEED_PX := 900.0
const CURSOR_SPEED_PX := 700.0
const HOVER_RADIUS_M := 40.0
const PLAYER_MARKER_PX := 14.0
const COMBO_ACTIONS := ["debug_toggle", "debug_graph", "reset_vehicle"]
const LEGEND_MARGIN_PX := 16.0
## The map's key-cap hints, one row each in the column's footer (human, 2026-10-07: "I wonder
## if we align those so the items are all on the right").
const HINT_ROWS := [
	[["L stick", "pan"], ["R stick", "cursor"]],
	[["LT / RT", "zoom"], ["Up / Down", "places"]],
	[["A", "open"], ["B", "back"], ["View / M", "close"]],
]
const LEGEND_ACTIONS := ["ui_up", "ui_down", "ui_accept", "ui_cancel"]

var renderer: MapRenderer
var graph: RoadGraph
var player: Node3D
## Same as Minimap.heading_source: the arrow follows the camera on foot, the car when driving.
var heading_source: Callable = Callable()
## The forecast strip in the map's corner (WeatherStrip); the scene sets its `weather`.
var strip: WeatherStrip
var zoom: float = 0.6:
	set(value):
		zoom = value
		if _focus_locked:
			_centre_on_focus()  # zooming keeps a picked place in the middle
var pan: Vector2 = Vector2.ZERO  # screen pixels offset from the player-centred view
var cursor: Vector2 = Vector2.ZERO  # screen pixels relative to the view centre
var hovered_edge: RoadGraph.RoadEdge
## Fixed places to mark and list (Services.Place: services and garages).
var places: Array = []:
	set(value):
		places = value
		if legend != null:
			legend.places = value
			legend.rebuild()
## The place picked in the legend, highlighted; the view stays centred on it until panned.
var focused: Services.Place
var legend: MapLegend
var _back_armed: bool = false
var _focus_locked: bool = false
var _hover_hidden: bool = false  # just picked a place: its label, not the road's, until the cursor moves

@onready var _view: Control = $View
@onready var _label: Label = $View/HoverLabel
@onready var _column: VBoxContainer = $View/Column
@onready var _title_bar: PanelContainer = $View/Column/TitleBar
@onready var _footer: PanelContainer = $View/Column/Footer
@onready var _hints: VBoxContainer = $View/Column/Footer/Hints


func _ready() -> void:
	visible = false
	strip = WeatherStrip.new()
	strip.name = "WeatherStrip"
	strip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	strip.position = Vector2(16.0, 16.0)
	add_child(strip)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view.draw.connect(_draw_view)
	_view.theme = MenuTheme.theme()
	# All of the map's UI is one column on the right: title, legend, then the hints as its footer.
	_column.offset_left = -MapLegend.WIDTH_PX - LEGEND_MARGIN_PX
	_column.offset_right = -LEGEND_MARGIN_PX
	_column.offset_top = LEGEND_MARGIN_PX
	_column.offset_bottom = -LEGEND_MARGIN_PX
	for pairs: Array in HINT_ROWS:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_hints.add_child(row)
		MenuTheme.hint_bar(row, pairs)
	legend = MapLegend.new()
	legend.name = "Legend"
	legend.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	legend.places = places
	legend.place_chosen.connect(focus_on)
	legend.back_out.connect(close)
	_column.add_child(legend)
	_column.move_child(legend, _title_bar.get_index() + 1)


func _input(event: InputEvent) -> void:
	# Typing in a text field (the report form, the join address): M is a letter, not the map.
	var focus := get_viewport().gui_get_focus_owner()
	if event is InputEventKey and (focus is LineEdit or focus is TextEdit):
		return
	# Back alone toggles the map; Back held with a debug button is a debug combo, not a toggle.
	if event.is_action_pressed("debug_modifier"):
		_back_armed = true
	for action in COMBO_ACTIONS:
		if event.is_action_pressed(action) and Input.is_action_pressed("debug_modifier"):
			_back_armed = false
	if event.is_action_released("debug_modifier") and _back_armed and event is InputEventJoypadButton:
		_back_armed = false
		toggle()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_action_pressed("map_toggle"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and legend_input(event):
		get_viewport().set_input_as_handled()


## The legend's buttons: Up / Down, A and B from the D-pad, keys or actions (not the sticks,
## which pan and move the cursor). Returns whether the event was used.
func legend_input(event: InputEvent) -> bool:
	if legend == null or event is InputEventJoypadMotion or event is InputEventMouse:
		return false
	for action: String in LEGEND_ACTIONS:
		if event.is_action_pressed(action, true):
			match action:
				"ui_up":
					legend.move(-1)
				"ui_down":
					legend.move(1)
				"ui_accept":
					legend.accept()
				"ui_cancel":
					legend.back()
			return true
	return false


## Centres the view on `place`, highlights it and keeps it centred through zooming until the
## player pans away.
func focus_on(place: Services.Place) -> void:
	focused = place
	_focus_locked = true
	_hover_hidden = true
	_centre_on_focus()
	cursor = focus_offset()  # the crosshair on the place, not over its name
	_view.queue_redraw()


func _centre_on_focus() -> void:
	if focused == null or renderer == null:
		return
	var centre_px := renderer.world_to_pixel(player.global_position.x, player.global_position.z) if player != null else Vector2.ZERO
	pan = -(renderer.world_to_pixel(focused.at.x, focused.at.z) - centre_px) * zoom + focus_offset()


## Where a picked place sits relative to the view's centre: the middle of the map left of the
## legend, so the panel doesn't cover it or its name.
func focus_offset() -> Vector2:
	if legend == null or not legend.visible:
		return Vector2.ZERO
	return Vector2(-(MapLegend.WIDTH_PX + LEGEND_MARGIN_PX) * 0.5, 0.0)


## The height the legend may take in the column: what's left after the title, the hints
## footer and the gaps between them.
func legend_room() -> float:
	var gap := float(_column.get_theme_constant("separation"))
	var column_h := _view.size.y - LEGEND_MARGIN_PX * 2.0
	return maxf(column_h - _title_bar.get_combined_minimum_size().y - _footer.get_combined_minimum_size().y - gap * 3.0, 0.0)


## The key-cap hints as plain text, one row per line (tests, logs).
func hint_text() -> String:
	var lines := PackedStringArray()
	for row in _hints.get_children():
		lines.append(MenuTheme.hint_text(row as HBoxContainer))
	return "\n".join(lines)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	pan = Vector2.ZERO
	cursor = Vector2.ZERO
	focused = null
	_focus_locked = false
	if legend != null:
		legend.origin = player
		legend.max_height = legend_room()
		legend.reset()
	MenuTheme.refresh_accent()
	get_tree().paused = true
	_view.queue_redraw()
	opened.emit()


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func _process(delta: float) -> void:
	if not visible or renderer == null or renderer.texture == null:
		return
	var zoom_in := Input.get_action_strength("accelerate")
	var zoom_out := Input.get_action_strength("brake")
	if zoom_in > 0.0 or zoom_out > 0.0:
		zoom = clampf(zoom * pow(ZOOM_SPEED, (zoom_in - zoom_out) * delta), ZOOM_MIN, ZOOM_MAX)
	var pan_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if pan_input != Vector2.ZERO:
		_focus_locked = false
	pan -= pan_input * PAN_SPEED_PX * delta
	var cursor_input := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if cursor_input != Vector2.ZERO:
		_hover_hidden = false
	cursor += cursor_input * CURSOR_SPEED_PX * delta
	var half := _view.size * 0.5
	cursor = cursor.clamp(-half, half)
	_update_hover()
	_view.queue_redraw()


## Screen position (relative to the view centre) of a world xz point.
func world_to_screen(x: float, z: float) -> Vector2:
	var centre_px := renderer.world_to_pixel(player.global_position.x, player.global_position.z) if player != null else Vector2.ZERO
	return (renderer.world_to_pixel(x, z) - centre_px) * zoom + pan


## World xz of a screen position relative to the view centre.
func screen_to_world(screen: Vector2) -> Vector2:
	var centre_px := renderer.world_to_pixel(player.global_position.x, player.global_position.z) if player != null else Vector2.ZERO
	return renderer.pixel_to_world((screen - pan) / zoom + centre_px)


func _update_hover() -> void:
	if graph == null or _hover_hidden:
		hovered_edge = null
		_label.visible = false
		return
	var w := screen_to_world(cursor)
	var hit := graph.nearest_edge(Vector3(w.x, 0.0, w.y), HOVER_RADIUS_M / zoom)
	hovered_edge = hit.get("edge") if not hit.is_empty() else null
	if hovered_edge != null:
		var name := hovered_edge.name if hovered_edge.name != "" else hovered_edge.road_class.replace("_", " ")
		_label.text = "%s%s" % [name, "  (one-way)" if hovered_edge.oneway else ""]
	else:
		_label.text = ""
	_label.visible = _label.text != ""
	_place_hover_label()


## Puts the road label by the cursor, flipped to its left when it would run into the column.
func _place_hover_label() -> void:
	_label.reset_size()
	_label.position = _view.size * 0.5 + cursor + Vector2(16, -12)
	var column_left := _column.position.x - LEGEND_MARGIN_PX
	if _label.position.x + _label.size.x > column_left:
		_label.position.x = maxf(_view.size.x * 0.5 + cursor.x - 16.0 - _label.size.x, LEGEND_MARGIN_PX)


func _draw_view() -> void:
	if renderer == null or renderer.texture == null:
		return
	var centre := _view.size * 0.5
	_view.draw_rect(Rect2(Vector2.ZERO, _view.size), MapRenderer.BACKGROUND)
	var origin := centre + world_to_screen(renderer.min_x, renderer.min_z)
	_view.draw_set_transform(origin, 0.0, Vector2(zoom, zoom))
	_view.draw_texture(renderer.texture, Vector2.ZERO)
	_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hovered_edge != null:
		var pts := PackedVector2Array()
		for p in hovered_edge.polyline:
			pts.append(centre + world_to_screen(p.x, p.z))
		_view.draw_polyline(pts, Color(1.0, 0.9, 0.2), maxf(3.0, MapRenderer.road_width_px(hovered_edge.road_class) * zoom + 2.0), true)
	_draw_places(centre)
	if player != null:
		var heading := heading_vector()
		var angle := atan2(heading.x, -heading.z)  # 0 = north (up on the map)
		var p := centre + pan
		var tip := p + Vector2(sin(angle), -cos(angle)) * PLAYER_MARKER_PX
		var left := p + Vector2(sin(angle + 2.5), -cos(angle + 2.5)) * PLAYER_MARKER_PX * 0.8
		var right := p + Vector2(sin(angle - 2.5), -cos(angle - 2.5)) * PLAYER_MARKER_PX * 0.8
		_view.draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1.0, 0.3, 0.25))
		var here := graph.nearest_edge(player.global_position, 30.0) if graph != null else {}
		if not here.is_empty():
			var e: RoadGraph.RoadEdge = here["edge"]
			var name := e.name if e.name != "" else e.road_class.replace("_", " ")
			_view.draw_string(ThemeDB.fallback_font, p + Vector2(-60, 34), "on " + name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.9, 0.9))
	var c := centre + cursor
	_view.draw_arc(c, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0, true)
	_view.draw_line(c + Vector2(-14, 0), c + Vector2(14, 0), Color(1, 1, 1, 0.6), 1.0)
	_view.draw_line(c + Vector2(0, -14), c + Vector2(0, 14), Color(1, 1, 1, 0.6), 1.0)


## Every place at screen size, the focused one last with a pulsing ring in the tone's accent
## and its name.
func _draw_places(centre: Vector2) -> void:
	var r := PlaceIcons.num("marker_radius_px", 9.0)
	var bounds := Rect2(Vector2.ZERO, _view.size).grow(r)
	for pl: Services.Place in places:
		if pl == focused:
			continue
		var at := centre + world_to_screen(pl.at.x, pl.at.z)
		if bounds.has_point(at):
			PlaceIcons.draw(_view, at, pl.kind, r)
	if focused == null:
		return
	var f := centre + world_to_screen(focused.at.x, focused.at.z)
	var accent := ContentMode.hud_accent()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU / PlaceIcons.num("highlight_pulse_s", 0.9))
	var ring := PlaceIcons.num("highlight_radius_px", 16.0)
	_view.draw_circle(f, ring + 4.0 * pulse, Color(accent, 0.25 + 0.2 * pulse))
	_view.draw_arc(f, ring + 4.0 * pulse, 0.0, TAU, 40, accent, 2.5, true)
	PlaceIcons.draw(_view, f, focused.kind, r * 1.25)
	var title := PlaceIcons.display_name(focused)
	_view.draw_string(ThemeDB.fallback_font, f + Vector2(ring + 10.0, 6.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.95))


## The player's facing for the arrow: the heading source when set, else the body's forward.
func heading_vector() -> Vector3:
	if heading_source.is_valid():
		var h: Vector3 = heading_source.call()
		h.y = 0.0
		if h.length_squared() > 1e-6:
			return h.normalized()
	return -player.global_basis.z if player != null else Vector3.FORWARD
