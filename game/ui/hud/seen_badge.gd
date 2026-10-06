class_name SeenBadge
extends Control
## The seen badge (update-police-pursuit 1.2): an eye beside the wanted stars that says
## whether the police can see the player, with no text so it reads in every tone and language.
## Seen: a solid eye, with a helicopter and/or a car mark beside it for who has them. Hidden: a
## hollow, closed eye that blinks, and a ring round it filling toward the time the current
## stars need to drop (`Wanted.hidden_progress`). Not wanted: nothing.

enum State { OFF, SEEN, HIDDEN }

const CONFIG_PATH := "res://ui/hud/hud_config.json"
const DARK := Color(0.05, 0.06, 0.08, 0.75)
const EYE_SEGMENTS := 16

var state: int = State.OFF
var heli_sees: bool = false
var ground_sees: bool = false
var progress: float = 0.0  # 0..1 while hidden
var _blink_t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(_mark_px() * 3.2 + _size_px() + 8.0, _size_px())
	size = custom_minimum_size


static func _tun() -> Dictionary:
	return WeaponWheel.config().get("seen_badge", {})


static func _size_px() -> float:
	return float(_tun().get("size_px", 44.0))


static func _mark_px() -> float:
	return float(_tun().get("mark_px", 16.0))


## The badge's state for a wanted level and who sees the player.
static func state_of(stars: int, heli: bool, ground: bool) -> int:
	if stars <= 0:
		return State.OFF
	return State.SEEN if heli or ground else State.HIDDEN


## Takes the wanted state for this frame.
func show_wanted(stars: int, heli: bool, ground: bool, hidden_progress: float) -> void:
	var was := state
	state = state_of(stars, heli, ground)
	heli_sees = heli and state == State.SEEN
	ground_sees = ground and state == State.SEEN
	progress = clampf(hidden_progress, 0.0, 1.0) if state == State.HIDDEN else 0.0
	if state != was:
		_blink_t = 0.0  # a fresh blink cycle starts on the change, so being spotted reads at once
	visible = state != State.OFF
	queue_redraw()


## The bright half of a blink (always bright while seen).
func blink_on() -> bool:
	if state != State.HIDDEN:
		return true
	var half := float(_tun().get("blink_s", 0.45))
	return fmod(_blink_t, half * 2.0) < half


func _process(delta: float) -> void:
	if state == State.HIDDEN:
		_blink_t += delta
		queue_redraw()


func _draw() -> void:
	if state == State.OFF:
		return
	var px := _size_px()
	var accent := ContentMode.hud_accent()
	var c := Vector2(size.x - px * 0.5, px * 0.5)
	draw_circle(c, px * 0.5, DARK)
	var w := px * 0.34
	var h := px * 0.2
	if state == State.SEEN:
		draw_colored_polygon(_almond(c, w, h), Color(0.96, 0.96, 0.98))
		draw_circle(c, h * 0.85, accent)
		draw_circle(c, h * 0.4, DARK)
	else:
		var a := 1.0 if blink_on() else float(_tun().get("hidden_alpha", 0.35))
		var outline := _almond(c, w, h)
		outline.append(outline[0])
		draw_polyline(outline, Color(0.96, 0.96, 0.98, a), 2.0, true)
		draw_line(c - Vector2(w * 0.8, 0.0), c + Vector2(w * 0.8, 0.0), Color(0.96, 0.96, 0.98, a), 2.0, true)
		var ring := float(_tun().get("ring_px", 3.0))
		draw_arc(c, px * 0.5 - ring * 0.5, 0.0, TAU, 40, Color(accent, 0.25), ring, true)
		if progress > 0.0:
			draw_arc(c, px * 0.5 - ring * 0.5, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, accent, ring, true)
	# Who has them, to the left of the eye, each on its own dark disc.
	var m := _mark_px()
	var x := size.x - px - 6.0 - m * 0.75
	if heli_sees:
		draw_circle(Vector2(x, px * 0.5), m * 0.75, DARK)
		_draw_helicopter(Vector2(x, px * 0.5), m)
		x -= m * 1.6
	if ground_sees:
		draw_circle(Vector2(x, px * 0.5), m * 0.75, DARK)
		_draw_car(Vector2(x, px * 0.5), m)


## An eye outline: two arcs meeting at the corners, `w` half-width, `h` half-height.
static func _almond(c: Vector2, w: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(EYE_SEGMENTS + 1):
		var t := float(i) / EYE_SEGMENTS
		pts.append(c + Vector2(-w + 2.0 * w * t, -h * sin(PI * t)))
	for i in range(EYE_SEGMENTS - 1, 0, -1):
		var t := float(i) / EYE_SEGMENTS
		pts.append(c + Vector2(-w + 2.0 * w * t, h * sin(PI * t)))
	return pts


func _draw_helicopter(c: Vector2, m: float) -> void:
	var col := Color(0.96, 0.96, 0.98)
	draw_circle(c + Vector2(0.0, m * 0.08), m * 0.26, col)  # cabin
	draw_line(c + Vector2(m * 0.15, m * 0.05), c + Vector2(m * 0.55, -m * 0.02), col, 2.0, true)  # tail
	draw_line(c + Vector2(-m * 0.5, -m * 0.3), c + Vector2(m * 0.5, -m * 0.3), col, 2.0, true)  # rotor
	draw_line(c + Vector2(0.0, -m * 0.3), c + Vector2(0.0, -m * 0.12), col, 1.5, true)


func _draw_car(c: Vector2, m: float) -> void:
	var col := Color(0.96, 0.96, 0.98)
	draw_rect(Rect2(c + Vector2(-m * 0.5, -m * 0.12), Vector2(m, m * 0.3)), col)  # body
	draw_rect(Rect2(c + Vector2(-m * 0.28, -m * 0.32), Vector2(m * 0.52, m * 0.22)), col)  # cabin
	draw_circle(c + Vector2(-m * 0.28, m * 0.2), m * 0.11, DARK)
	draw_circle(c + Vector2(m * 0.28, m * 0.2), m * 0.11, DARK)
