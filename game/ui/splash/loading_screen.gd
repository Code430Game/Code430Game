class_name LoadingScreen
extends CanvasLayer
## The splash card again, with a progress bar and what is loading under it, shown from the
## moment the boot splash goes until the map is playable: on the Deck, three districts take long
## enough that a still picture looks hung. The bar never goes backwards.

const BAR_SIZE := Vector2(640, 10)
const SplashCard := preload("res://ui/splash/splash_card.gd")

var _bar: ProgressBar
var _text: Label


func _init() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	SplashCard.build(root)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_top = 180  # under the tagline, clear of the credits and the call to help
	col.offset_bottom = 240
	col.offset_left = -BAR_SIZE.x * 0.5
	col.offset_right = BAR_SIZE.x * 0.5
	col.add_theme_constant_override("separation", 10)
	root.add_child(col)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = BAR_SIZE
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	var fill := StyleBoxFlat.new()
	fill.bg_color = SplashCard.ACCENT
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(_bar)
	_text = Label.new()
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.add_theme_font_size_override("font_size", 20)
	_text.add_theme_color_override("font_color", SplashCard.DIM)
	col.add_child(_text)
	set_progress(0.0, "Loading...")


## Shows `fraction` (0 to 1) done, on `text`.
func set_progress(fraction: float, text: String) -> void:
	_bar.value = maxf(_bar.value, clampf(fraction, 0.0, 1.0))
	_text.text = text


func progress() -> float:
	return _bar.value


func status_text() -> String:
	return _text.text
