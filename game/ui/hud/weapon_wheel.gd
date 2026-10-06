class_name WeaponWheel
extends Control
## The weapon wheel (add-weapon-selector). Held LB / Tab opens it (the Shooter decides tap
## against hold); the right stick or the mouse points at a segment and the release takes it;
## B / Esc closes it without a change. One round tile per entry of the page, the first at the
## top and the rest clockwise, on a thin ring around an open hub that names the pointed-at
## entry. Past `max_segments` the rest go on an outer ring, reached by pushing the stick all
## the way (or the mouse past the inner ring). The game never pauses or slows while it is open:
## co-op players share the world.
##
## Pages are kinds of things (`WheelPage`); with more than one, RB / Q steps between them and
## the page title shows above the ring. This node sits on its own canvas layer after the pause
## menu so its `_input` sees B / Esc first.

signal closed(taken: bool)

const CONFIG_PATH := "res://ui/hud/hud_config.json"
## How long after a close the Shooter ignores fire and reload (the B that cancelled is reload).
const CLOSE_GRACE_MS := 150

static var _config: Dictionary = {}

var pages: Array[WheelPage] = []
var page: int = 0
## The pointed-at segment, or -1.
var selected: int = -1
var closed_at_ms: int = -100000
var _open: bool = false
var _mouse: Vector2 = Vector2.ZERO
var _by_stick: bool = false
var _entries: Array[Dictionary] = []


## The whole HUD config file (hud_config.json), loaded once.
static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config = parsed if parsed is Dictionary else {"wheel": {}, "tile": {}}
	return _config


## The wheel's tunables.
static func tunables() -> Dictionary:
	return config().get("wheel", {})


## Screen angle of segment `i` of `n` (radians, y down): the first at the top, then clockwise.
static func segment_angle(i: int, n: int) -> float:
	return -PI * 0.5 + TAU * float(i) / float(maxi(n, 1))


## The segment of `n` nearest the direction `dir` (screen space, y down), or -1 for none.
static func segment_for(dir: Vector2, n: int) -> int:
	if n <= 0 or dir == Vector2.ZERO:
		return -1
	var rel := fposmod(dir.angle() + PI * 0.5, TAU)
	return int(round(rel / (TAU / float(n)))) % n


## How many of `n` entries sit on the inner and the outer ring.
static func ring_counts(n: int, max_segments: int) -> Vector2i:
	var inner := mini(n, maxi(max_segments, 1))
	return Vector2i(inner, n - inner)


## The entry for a pointer at `dir`; `outer` when it is pushed past the inner ring.
static func pick(dir: Vector2, outer: bool, n: int, max_segments: int) -> int:
	var c := ring_counts(n, max_segments)
	if outer and c.y > 0:
		return c.x + segment_for(dir, c.y)
	return segment_for(dir, c.x)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # icons are imported at 2x
	visible = false


func _ready() -> void:
	ContentMode.mode_changed.connect(_on_mode_changed)


func _on_mode_changed(_id: String) -> void:
	rebuild()


func is_open() -> bool:
	return _open


## True for a moment after the wheel closed, so the press that closed it does nothing else.
func just_closed() -> bool:
	return Time.get_ticks_msec() - closed_at_ms < CLOSE_GRACE_MS


func entries() -> Array[Dictionary]:
	return _entries


func open_wheel() -> void:
	if pages.is_empty() or _open:
		return
	page = clampi(page, 0, pages.size() - 1)
	_open = true
	_mouse = Vector2.ZERO
	_by_stick = false
	selected = -1
	rebuild()
	visible = true


## Closes the wheel; `take` puts the pointed-at entry in use. Returns true when it did.
func close(take: bool) -> bool:
	if not _open:
		return false
	var took := take and selected >= 0 and selected < _entries.size()
	if took:
		pages[page].choose(selected)
	_open = false
	visible = false
	selected = -1
	closed_at_ms = Time.get_ticks_msec()
	closed.emit(took)
	return took


## Points at entry `i` (-1 for none), as the stick or mouse would.
func select(i: int) -> void:
	selected = i if i >= 0 and i < _entries.size() else -1
	queue_redraw()


## Steps `dir` pages round; nothing with a single page.
func step_page(dir: int) -> void:
	if pages.size() < 2:
		return
	page = posmod(page + dir, pages.size())
	selected = -1
	_mouse = Vector2.ZERO
	rebuild()


## Re-reads the page's entries (a tone change swaps names and icons).
func rebuild() -> void:
	_entries = pages[page].entries() if page < pages.size() else ([] as Array[Dictionary])
	if selected >= _entries.size():
		selected = -1
	queue_redraw()


## The right stick this frame. Past the deadzone it points; back in the middle it lets go.
func steer(stick: Vector2) -> void:
	if not _open:
		return
	var t := tunables()
	if stick.length() >= float(t.get("deadzone", 0.45)):
		_by_stick = true
		_point(stick, stick.length() >= float(t.get("outer_stick", 0.95)))
	elif _by_stick and selected >= 0:
		selected = -1
		queue_redraw()


## Mouse movement since the wheel opened, in pixels.
func move_mouse(relative: Vector2) -> void:
	if not _open:
		return
	_by_stick = false
	_mouse += relative
	var t := tunables()
	var s := hud_scale()
	if _mouse.length() >= float(t.get("mouse_px", 40.0)) * s:
		_point(_mouse, _mouse.length() >= float(t.get("radius_px", 150.0)) * s * 1.3)


func _point(dir: Vector2, outer: bool) -> void:
	var i := pick(dir, outer, _entries.size(), int(tunables().get("max_segments", 8)))
	if i != selected:
		selected = i
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion:
		move_mouse((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()  # no looking around while choosing
	elif event.is_action_pressed("ui_cancel"):
		close(false)
		get_viewport().set_input_as_handled()  # Esc closes the wheel, not opens the pause menu
	elif event.is_action_pressed("wheel_page"):
		step_page(1)
		get_viewport().set_input_as_handled()


## HUD pixels per design pixel (sizes in hud_config.json are at 1280x800).
func hud_scale() -> float:
	return get_viewport_rect().size.y / 800.0 if is_inside_tree() else 1.0


func _draw() -> void:
	if not _open or _entries.is_empty():
		return
	var t := tunables()
	var s := hud_scale()
	var centre := get_viewport_rect().size * 0.5
	var radius := float(t.get("radius_px", 150.0)) * s
	var tile_r := float(t.get("tile_px", 64.0)) * s * 0.5
	var accent := ContentMode.hud_accent()
	var dark := Color(0.05, 0.06, 0.08, 0.82)
	var counts := ring_counts(_entries.size(), int(t.get("max_segments", 8)))
	var font := get_theme_default_font()
	var outer_r := radius * (float(t.get("outer_scale", 1.6)) if counts.y > 0 else 1.0)
	draw_circle(centre, outer_r + tile_r + 10.0 * s, Color(0, 0, 0, 0.22))  # a soft backdrop against bright sky
	draw_arc(centre, radius, 0.0, TAU, 96, Color(1, 1, 1, 0.22), 2.0 * s, true)
	if counts.y > 0:
		draw_arc(centre, radius * float(t.get("outer_scale", 1.6)), 0.0, TAU, 128, Color(1, 1, 1, 0.22), 2.0 * s, true)
	draw_circle(centre, float(t.get("hub_px", 110.0)) * s * 0.5, dark)
	draw_arc(centre, float(t.get("hub_px", 110.0)) * s * 0.5, 0.0, TAU, 64, Color(accent, 0.6), 2.0 * s, true)
	var current := pages[page].current_index()
	for i in range(_entries.size()):
		var e: Dictionary = _entries[i]
		var outer := i >= counts.x
		var k := i - counts.x if outer else i
		var ring_r := radius * (float(t.get("outer_scale", 1.6)) if outer else 1.0)
		var pos := centre + Vector2.from_angle(segment_angle(k, counts.y if outer else counts.x)) * ring_r
		var r := tile_r * (float(t.get("selected_scale", 1.15)) if i == selected else 1.0)
		draw_circle(pos, r, dark)
		if i == selected:
			draw_circle(pos, r, Color(accent, 0.28))
			draw_arc(pos, r, 0.0, TAU, 48, accent, 3.0 * s, true)
		elif i == current:
			draw_arc(pos, r - 1.5 * s, 0.0, TAU, 48, Color(accent, 0.85), 1.5 * s, true)
		var tex: Texture2D = e.get("icon")
		if tex != null:
			var tint := accent if i == selected else Color(1, 1, 1, 0.92 if bool(e.get("enabled", true)) else 0.35)
			draw_texture_rect(tex, Rect2(pos - Vector2.ONE * r * 0.7, Vector2.ONE * r * 1.4), false, tint)
	var shown := selected if selected >= 0 else current
	if shown >= 0 and shown < _entries.size():
		_text_centred(font, centre + Vector2(0, -2.0 * s), str(_entries[shown].get("name", "")), int(19 * s), Color.WHITE)
		var sub := str(_entries[shown].get("sub", ""))
		if sub != "":
			_text_centred(font, centre + Vector2(0, 20.0 * s), sub, int(15 * s), Color(accent, 0.95))
	if pages.size() > 1:
		var top := centre.y - radius * (float(t.get("outer_scale", 1.6)) if counts.y > 0 else 1.0) - tile_r - 34.0 * s
		_text_centred(font, Vector2(centre.x, top), pages[page].title(), int(20 * s), Color.WHITE)
		for d in range(pages.size()):
			var at := Vector2(centre.x + (float(d) - float(pages.size() - 1) * 0.5) * 14.0 * s, top + 14.0 * s)
			draw_circle(at, 3.5 * s, accent if d == page else Color(1, 1, 1, 0.4))


func _text_centred(font: Font, at: Vector2, text: String, size_px: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var p := at - Vector2(w * 0.5, 0.0)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(0, 0, 0, 0.9))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
