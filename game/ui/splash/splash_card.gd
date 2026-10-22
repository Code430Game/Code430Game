extends Control
## The Code 430 splash card: the wordmark, "Made with Godot Engine" with Godot's icon, the
## OpenStreetMap credit, and a call to help at the GitHub repository. It is rendered once to
## `res://assets/splash/boot_splash.png` (scripts/render-splash.sh), which project.godot shows
## as the boot splash while the game loads. With `--render-to=path` it draws itself off screen at
## RENDER_SIZE, saves that there and quits.

const BG := Color(0.06, 0.07, 0.09)
const ACCENT := Color(0.85, 0.64, 0.25)  # gritty's HUD accent
const TEXT := Color(0.92, 0.93, 0.95)
const DIM := Color(0.62, 0.65, 0.7)
const REPO_URL := "github.com/Code430Game/Code430Game"
const GODOT_ICON := preload("res://assets/splash/godot_icon.svg")
const RENDER_SIZE := Vector2i(1920, 1200)  # the Deck's 16:10, twice over


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--render-to="):
			_render(arg.get_slice("=", 1))
			return
	build(self)


## Fills `root` (a full-size Control) with the card.
static func build(root: Control) -> void:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	root.add_child(col)
	col.add_child(_label("CODE 430", 132, TEXT, 18))
	var rule := ColorRect.new()
	rule.color = ACCENT
	rule.custom_minimum_size = Vector2(420, 6)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(rule)
	col.add_child(_label("An open-world city game, built from real maps", 30, DIM))
	col.add_child(_spacer(70))
	col.add_child(_label("Help us improve it", 34, ACCENT))
	col.add_child(_label(REPO_URL, 30, TEXT))
	# Credits along the bottom: Godot on the left, OpenStreetMap on the right.
	var foot := HBoxContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -96
	foot.offset_bottom = -36
	foot.offset_left = 48
	foot.offset_right = -48
	root.add_child(foot)
	var icon := TextureRect.new()
	icon.texture = GODOT_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(56, 56)
	foot.add_child(icon)
	foot.add_child(_spacer(12, true))
	foot.add_child(_label("Made with Godot Engine", 24, DIM))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	foot.add_child(_label("Map data © OpenStreetMap contributors", 24, DIM))


static func _label(text: String, size: int, color: Color, spacing: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if spacing > 0:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 1.0
		fv.spacing_glyph = spacing
		l.add_theme_font_override("font", fv)
	return l


static func _spacer(px: int, horizontal: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, 0) if horizontal else Vector2(0, px)
	return c


func _render(path: String) -> void:
	var vp := SubViewport.new()
	vp.size = RENDER_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var card := Control.new()
	card.size = Vector2(RENDER_SIZE)
	vp.add_child(card)
	build(card)
	for i in range(4):
		await RenderingServer.frame_post_draw
	var err := vp.get_texture().get_image().save_png(path)
	print("splash: %s (%s)" % [path, error_string(err)])
	get_tree().quit()
