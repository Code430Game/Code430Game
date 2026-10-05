class_name HoldRing
extends Control
## A ring that fills while a hold action builds up (reset a stuck car: hold R3), with its label
## beside it. Hidden at zero.

const RADIUS_PX := 18.0
const WIDTH_PX := 5.0

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		visible = progress > 0.0
		queue_redraw()
var text: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(RADIUS_PX * 2.0 + 8.0, RADIUS_PX * 2.0 + 8.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _draw() -> void:
	var c := Vector2(RADIUS_PX + 4.0, RADIUS_PX + 4.0)
	draw_arc(c, RADIUS_PX, 0.0, TAU, 48, Color(0, 0, 0, 0.5), WIDTH_PX + 2.0, true)
	draw_arc(c, RADIUS_PX, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, Color(1, 1, 1, 0.95), WIDTH_PX, true)
	if text != "":
		var font := get_theme_default_font()
		draw_string_outline(font, c + Vector2(RADIUS_PX + 10.0, 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
		draw_string(font, c + Vector2(RADIUS_PX + 10.0, 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
