class_name HeatGlyph
extends Control
## The gang heat glyph (add-hostile-gang 2.3): a tag mark on a dark disc beside the seen badge
## that shows how much the crew wants the player, as a ring filling round it. Inside turf the
## mark is solid; outside, while the heat drains, it dims. In clean the same glyph counts the
## paint tags on the player under it. Nothing is shown while the heat is zero.

const DARK := Color(0.05, 0.06, 0.08, 0.75)
const INK := Color(0.96, 0.96, 0.98)

var heat: float = 0.0  # 0..1
var in_turf: bool = false
var tags: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(_size_px(), _size_px())
	size = custom_minimum_size


static func _tun() -> Dictionary:
	return WeaponWheel.config().get("heat_glyph", {})


static func _size_px() -> float:
	return float(_tun().get("size_px", 44.0))


## Takes the heat for this frame.
func show_heat(value: float, inside: bool, tag_count: int = 0) -> void:
	heat = clampf(value, 0.0, 1.0)
	in_turf = inside
	tags = tag_count
	visible = heat > 0.0 or tags > 0
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var px := _size_px()
	var accent := ContentMode.hud_accent()
	var c := Vector2(px * 0.5, px * 0.5)
	draw_circle(c, px * 0.5, DARK)
	var a := 1.0 if in_turf else float(_tun().get("outside_alpha", 0.45))
	var ink := Color(INK, a)
	# Two crossed bats and a tag under them: the faction mark.
	var r := px * 0.22
	draw_line(c + Vector2(-r, -r), c + Vector2(r * 0.6, r * 0.6), ink, 3.0, true)
	draw_line(c + Vector2(r, -r), c + Vector2(-r * 0.6, r * 0.6), ink, 3.0, true)
	draw_rect(Rect2(c + Vector2(-r * 0.8, r * 0.35), Vector2(r * 1.6, r * 0.45)), ink)
	var ring := float(_tun().get("ring_px", 3.0))
	draw_arc(c, px * 0.5 - ring * 0.5, 0.0, TAU, 40, Color(accent, 0.25), ring, true)
	if heat > 0.0:
		draw_arc(c, px * 0.5 - ring * 0.5, -PI * 0.5, -PI * 0.5 + TAU * heat, 40, accent, ring, true)
	if tags > 0:
		var f := ThemeDB.fallback_font
		var text := "x%d" % tags
		draw_string(f, Vector2(px * 0.5 - 8.0, px + 12.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
