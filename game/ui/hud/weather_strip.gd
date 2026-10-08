class_name WeatherStrip
extends Control
## The weather forecast above the minimap, like a glance at a weather app: a glyph and the
## state now, then the state that follows and the real minutes until it starts to change
## (weather runs on real time, so the number is what the player will wait), or "<next> now"
## while a change is under way. Glyphs are drawn in code in the menu theme's text colour;
## a pinned session or a guest without a forecast shows only the state. Nothing changes by tone.

const WIDTH_PX := 220.0
const HEIGHT_PX := 30.0
const GLYPH_PX := 18.0
const PAD_PX := 8.0
const REFRESH_S := 1.0

var weather: WeatherController
## The last forecast rendered ({state, next, changing, seconds_left}), refreshed once a second.
var shown: Dictionary = {}
var _since: float = REFRESH_S
var _text_color: Color = Color(0.925, 0.933, 0.949)
var _bg: Color = Color(0.055, 0.063, 0.078, 0.85)
var _border: Color = Color(0.23, 0.25, 0.29)
var _font_px: int = 16


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH_PX, HEIGHT_PX)
	size = custom_minimum_size
	var data := MenuTheme.load_data()
	_text_color = MenuTheme.color(data, "text", _text_color)
	var strip := MenuTheme.color(data, "strip", Color(0.055, 0.063, 0.078))
	_bg = Color(strip.r, strip.g, strip.b, 0.85)
	_border = MenuTheme.color(data, "border", _border)
	_font_px = int(MenuTheme.num(data, "fonts", "small", 16))


func _process(delta: float) -> void:
	_since += delta
	if _since >= REFRESH_S:
		_since = 0.0
		refresh()


## Reads the controller's forecast and redraws. Safe to call from tests without a frame.
func refresh() -> void:
	if weather == null:
		shown = {}
		visible = false
		return
	shown = weather.forecast()
	visible = true
	queue_redraw()


## The glyph a state draws with: sun, cloud, rain, snow or fog (unknown states draw a cloud).
static func glyph_for(state: String) -> String:
	match state:
		"clear":
			return "sun"
		"rain":
			return "rain"
		"snow":
			return "snow"
		"fog":
			return "fog"
	return "cloud"


## Whole real minutes until the change starts, at least 1 while any time is left.
static func minutes_left(seconds_left: float) -> int:
	return int(ceil(seconds_left / 60.0)) if seconds_left > 0.0 else 0


## The strip's words for a forecast: "Clear", "Clear  Overcast in 12 min", "Overcast  Rain now".
static func text_for(f: Dictionary) -> String:
	var now := str(f.get("state", "")).capitalize()
	var next := str(f.get("next", ""))
	if next == "":
		return now
	if bool(f.get("changing", false)):
		return "%s  %s now" % [now, next.capitalize()]
	return "%s  %s in %d min" % [now, next.capitalize(), minutes_left(float(f.get("seconds_left", 0.0)))]


## The text the strip is showing (tests).
func text() -> String:
	return text_for(shown)


func _draw() -> void:
	if shown.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), _bg)
	draw_rect(Rect2(Vector2.ZERO, size), _border, false, 1.0)
	var font := ThemeDB.fallback_font
	var x := PAD_PX
	var mid := size.y * 0.5
	var baseline := mid + float(_font_px) * 0.36
	var now := str(shown.get("state", ""))
	draw_glyph(self, glyph_for(now), Vector2(x + GLYPH_PX * 0.5, mid), GLYPH_PX, _text_color)
	x += GLYPH_PX + 6.0
	var now_text := now.capitalize()
	draw_string(font, Vector2(x, baseline), now_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px, _text_color)
	x += font.get_string_size(now_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px).x + 10.0
	var next := str(shown.get("next", ""))
	if next == "":
		return
	# An arrow, then the follower's glyph and its timing.
	draw_line(Vector2(x, mid), Vector2(x + 10.0, mid), _text_color, 1.5)
	draw_line(Vector2(x + 10.0, mid), Vector2(x + 6.0, mid - 3.5), _text_color, 1.5)
	draw_line(Vector2(x + 10.0, mid), Vector2(x + 6.0, mid + 3.5), _text_color, 1.5)
	x += 16.0
	draw_glyph(self, glyph_for(next), Vector2(x + GLYPH_PX * 0.5, mid), GLYPH_PX, _text_color)
	x += GLYPH_PX + 6.0
	var when := "now" if bool(shown.get("changing", false)) else "in %d min" % minutes_left(float(shown.get("seconds_left", 0.0)))
	draw_string(font, Vector2(x, baseline), "%s %s" % [next.capitalize(), when], HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px, _text_color)


## Draws one weather glyph centred on `at`, `px` tall, with lines in `c`.
static func draw_glyph(on: CanvasItem, kind: String, at: Vector2, px: float, c: Color) -> void:
	var r := px * 0.5
	match kind:
		"sun":
			on.draw_circle(at, r * 0.42, c)
			for k in range(8):
				var d := Vector2.RIGHT.rotated(TAU * float(k) / 8.0)
				on.draw_line(at + d * r * 0.62, at + d * r * 0.95, c, 1.5)
		"fog":
			for k in range(3):
				var y := at.y + (float(k) - 1.0) * r * 0.55
				var inset := r * (0.15 if k == 1 else 0.0)
				on.draw_line(Vector2(at.x - r + inset, y), Vector2(at.x + r - inset, y), c, 2.0)
		_:
			_draw_cloud(on, at + Vector2(0.0, -r * 0.15 if kind != "cloud" else 0.0), r, c)
			if kind == "rain":
				for k in range(3):
					var x := at.x + (float(k) - 1.0) * r * 0.5
					on.draw_line(Vector2(x + r * 0.1, at.y + r * 0.35), Vector2(x - r * 0.1, at.y + r * 0.9), c, 1.5)
			elif kind == "snow":
				for k in range(3):
					var x := at.x + (float(k) - 1.0) * r * 0.5
					on.draw_circle(Vector2(x, at.y + r * 0.65), r * 0.12, c)


static func _draw_cloud(on: CanvasItem, at: Vector2, r: float, c: Color) -> void:
	on.draw_circle(at + Vector2(-r * 0.35, r * 0.1), r * 0.38, c)
	on.draw_circle(at + Vector2(r * 0.05, -r * 0.15), r * 0.5, c)
	on.draw_circle(at + Vector2(r * 0.45, r * 0.12), r * 0.36, c)
	on.draw_rect(Rect2(at + Vector2(-r * 0.4, r * 0.1), Vector2(r * 1.25, r * 0.38)), c)
