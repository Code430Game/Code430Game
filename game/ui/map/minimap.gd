class_name Minimap
extends Control
## Corner minimap: a crop of the map texture around the player, rotated so the
## car's heading points up. One textured quad per frame, no extra rendering.

const VIEW_RADIUS_M := 180.0
const PLAYER_MARKER_PX := 8.0
const BORDER := Color(0.85, 0.85, 0.85, 0.7)
const COMPASS_INSET_PX := 12.0
const COMPASS_COLOR := Color(1.0, 1.0, 1.0, 0.9)

var renderer: MapRenderer
var player: Node3D
## Moving markers set each frame by the scene: [{"at": Vector3, "color": Color}] (ambulances
## on a call). Drawn as small crosses.
var blips: Array = []


func _process(_delta: float) -> void:
	queue_redraw()


## Rotation to apply to the map so `heading` (world xz forward) points up on screen.
static func map_rotation_for(heading: Vector3) -> float:
	return -atan2(heading.x, -heading.z)


## Unit screen direction of world north on a map rotated by `rot` (up is -y on screen).
static func north_on_screen(rot: float) -> Vector2:
	return Vector2(0.0, -1.0).rotated(rot)


func _draw() -> void:
	if renderer == null or renderer.texture == null or player == null:
		return
	var centre := size * 0.5
	var scale := (size.x * 0.5) / VIEW_RADIUS_M * renderer.metres_per_pixel
	var rot := map_rotation_for(-player.global_basis.z)
	var player_px := renderer.world_to_pixel(player.global_position.x, player.global_position.z)
	draw_rect(Rect2(Vector2.ZERO, size), MapRenderer.BACKGROUND)
	draw_set_transform(centre, rot, Vector2(scale, scale))
	draw_texture(renderer.texture, -player_px)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b: Dictionary in blips:
		var at: Vector3 = b["at"]
		var off := (renderer.world_to_pixel(at.x, at.z) - player_px) * scale
		var px := centre + off.rotated(rot)
		if Rect2(Vector2.ZERO, size).grow(-4.0).has_point(px):
			var c: Color = b.get("color", Color.WHITE)
			draw_rect(Rect2(px - Vector2(5, 5), Vector2(10, 10)), Color(1, 1, 1, 0.9))
			draw_rect(Rect2(px - Vector2(1.5, 4), Vector2(3, 8)), c)
			draw_rect(Rect2(px - Vector2(4, 1.5), Vector2(8, 3)), c)
	var tip := centre + Vector2(0, -PLAYER_MARKER_PX)
	var left := centre + Vector2(-PLAYER_MARKER_PX * 0.7, PLAYER_MARKER_PX * 0.7)
	var right := centre + Vector2(PLAYER_MARKER_PX * 0.7, PLAYER_MARKER_PX * 0.7)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1.0, 0.3, 0.25))
	_draw_compass(centre, rot)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER, false, 2.0)


## N at the rim where north points, with short ticks for the other three directions.
func _draw_compass(centre: Vector2, rot: float) -> void:
	var radius := size.x * 0.5 - COMPASS_INSET_PX
	var north := north_on_screen(rot)
	var font := ThemeDB.fallback_font
	for k in range(4):
		var dir := north.rotated(PI * 0.5 * k)
		var at := centre + dir * radius
		if k == 0:
			draw_circle(at, 8.0, Color(0.1, 0.1, 0.12, 0.8))
			draw_string(font, at + Vector2(-4.5, 5.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COMPASS_COLOR)
		else:
			draw_line(at - dir * 3.0, at + dir * 3.0, COMPASS_COLOR, 2.0)
