class_name WeaponTile
extends Control
## The idle tile (add-weapon-selector): a small round tile with the icon of what is in hand,
## always shown on foot so empty hands are visible too. A slot change flashes it in the tone's
## accent for `flash_s`.

var icon: Texture2D
var _flash_left: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # icons are imported at 2x
	var px := _size_px()
	custom_minimum_size = Vector2(px, px)
	size = custom_minimum_size


static func _tun() -> Dictionary:
	return WeaponWheel.config().get("tile", {})


static func _size_px() -> float:
	return float(_tun().get("size_px", 40.0))


## Shows `tex` (what is in hand now) without a flash.
func show_icon(tex: Texture2D) -> void:
	icon = tex
	queue_redraw()


## Lights the tile in the accent for `flash_s`.
func flash() -> void:
	_flash_left = float(_tun().get("flash_s", 0.6))
	queue_redraw()


func flashing() -> bool:
	return _flash_left > 0.0


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var px := _size_px()
	var c := Vector2(px, px) * 0.5
	var t := _flash_left / maxf(float(_tun().get("flash_s", 0.6)), 0.001)
	var accent := ContentMode.hud_accent()
	var alpha := lerpf(float(_tun().get("opacity", 0.7)), 1.0, t)
	draw_circle(c, px * 0.5, Color(0.05, 0.06, 0.08, 0.75 * alpha))
	if t > 0.0:
		draw_arc(c, px * 0.5 - 1.5, 0.0, TAU, 40, Color(accent, t), 2.5, true)
	if icon != null:
		draw_texture_rect(icon, Rect2(c - Vector2.ONE * px * 0.32, Vector2.ONE * px * 0.64), false, Color(Color.WHITE.lerp(accent, t), alpha))
