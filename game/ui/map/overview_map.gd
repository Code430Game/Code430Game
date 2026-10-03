class_name OverviewMap
extends CanvasLayer
## Full-screen map (the pause-menu map). Toggled with `map_toggle` (Back alone, or M).
## Pauses the game while open. Left stick pans, right stick moves the cursor,
## triggers zoom, and the road under the cursor is highlighted and named.

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

var renderer: MapRenderer
var graph: RoadGraph
var player: Node3D
var zoom: float = 0.6
var pan: Vector2 = Vector2.ZERO  # screen pixels offset from the player-centred view
var cursor: Vector2 = Vector2.ZERO  # screen pixels relative to the view centre
var hovered_edge: RoadGraph.RoadEdge
var _back_armed: bool = false

@onready var _view: Control = $View
@onready var _label: Label = $View/HoverLabel
@onready var _title: Label = $View/Title


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view.draw.connect(_draw_view)


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


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	pan = Vector2.ZERO
	cursor = Vector2.ZERO
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
	pan -= pan_input * PAN_SPEED_PX * delta
	var cursor_input := Input.get_vector("look_left", "look_right", "look_up", "look_down")
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
	if graph == null:
		hovered_edge = null
		return
	var w := screen_to_world(cursor)
	var hit := graph.nearest_edge(Vector3(w.x, 0.0, w.y), HOVER_RADIUS_M / zoom)
	hovered_edge = hit.get("edge") if not hit.is_empty() else null
	if hovered_edge != null:
		var name := hovered_edge.name if hovered_edge.name != "" else hovered_edge.road_class.replace("_", " ")
		_label.text = "%s%s" % [name, "  (one-way)" if hovered_edge.oneway else ""]
	else:
		_label.text = ""
	_label.position = _view.size * 0.5 + cursor + Vector2(16, -12)


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
	if player != null:
		var heading := -player.global_basis.z
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
