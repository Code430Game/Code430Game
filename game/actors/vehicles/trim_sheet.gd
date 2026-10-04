class_name TrimSheet
extends RefCounted
## One 256 x 256 atlas of vehicle details, drawn in code at first use and shared by every
## vehicle: grille, plate, lens, door seam, window tint, check stripe, roof sign, roller door.
## Cells are 32 px; `uv_rect(cell)` gives the UV rectangle the generator maps a detail quad
## to. The blank cell is white, so body vertices (white) mapped there show the instance colour
## untouched. Deterministic: the same pixels every run, no file on disk.

const SIZE := 256
const CELL := 32
const PAD := 2  # px kept clear at each cell edge so mipmaps don't bleed neighbours in
## Cell name -> (column, row).
const CELLS := {
	"blank": Vector2i(0, 0),
	"grille": Vector2i(1, 0),
	"plate": Vector2i(2, 0),
	"lens": Vector2i(3, 0),
	"seam": Vector2i(4, 0),
	"tint": Vector2i(5, 0),
	"check": Vector2i(6, 0),
	"dark": Vector2i(7, 0),
	"roof_sign": Vector2i(0, 1),
	"roller": Vector2i(1, 1),
}

static var _texture: ImageTexture = null
static var _image: Image = null


## The atlas texture (built once).
static func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(image())
	return _texture


## The atlas image (built once; `build_image` makes a fresh one).
static func image() -> Image:
	if _image == null:
		_image = build_image()
		_image.generate_mipmaps()
	return _image


## UV rectangle of a cell, inset by the padding.
static func uv_rect(cell: String) -> Rect2:
	var c: Vector2i = CELLS.get(cell, CELLS["blank"])
	var px := Vector2(c.x * CELL + PAD, c.y * CELL + PAD)
	return Rect2(px / SIZE, Vector2(CELL - PAD * 2, CELL - PAD * 2) / SIZE)


## UV at the centre of a cell (for faces that take a cell's flat colour).
static func uv_centre(cell: String) -> Vector2:
	var r := uv_rect(cell)
	return r.position + r.size * 0.5


static func build_image() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_draw_cell(img, "grille", func(x: int, y: int) -> Color:
		return Color(0.05, 0.05, 0.06) if y % 6 < 3 else Color(0.22, 0.22, 0.24))
	_draw_cell(img, "plate", func(x: int, y: int) -> Color:
		if x < 2 or y < 2 or x > CELL - 3 or y > CELL - 3:
			return Color(0.15, 0.2, 0.45)  # border
		# A row of blocky made-up glyphs: never a real plate.
		var gx := (x - 4) / 4
		if y >= 11 and y <= 20 and x >= 4 and x < 28 and (x - 4) % 4 < 3 and ((gx * 7 + y / 3) % 5) != 0:
			return Color(0.12, 0.12, 0.14)
		return Color(0.93, 0.93, 0.9))
	_draw_cell(img, "lens", func(x: int, y: int) -> Color:
		var d := Vector2(x - CELL * 0.5 + 0.5, y - CELL * 0.5 + 0.5).length() / (CELL * 0.5)
		return Color(1, 1, 1).lerp(Color(0.72, 0.72, 0.72), clampf(d, 0.0, 1.0)))
	_draw_cell(img, "seam", func(x: int, y: int) -> Color:
		return Color(0.35, 0.35, 0.35) if absi(x - CELL / 2) < 1 else Color.WHITE)
	_draw_cell(img, "tint", func(x: int, y: int) -> Color:
		return Color(0.2, 0.24, 0.3).lerp(Color(0.1, 0.12, 0.16), float(y) / CELL))
	_draw_cell(img, "check", func(x: int, y: int) -> Color:
		return Color(0.06, 0.06, 0.06) if ((x / 4) + (y / 4)) % 2 == 0 else Color.WHITE)
	_draw_cell(img, "dark", func(x: int, y: int) -> Color:
		return Color(0.09, 0.09, 0.1))
	_draw_cell(img, "roof_sign", func(x: int, y: int) -> Color:
		if y >= 12 and y <= 19 and x >= 5 and x < 27 and (x - 5) % 6 < 4:
			return Color(0.1, 0.1, 0.1)  # four block letters
		return Color(1.0, 0.95, 0.7))
	_draw_cell(img, "roller", func(x: int, y: int) -> Color:
		return Color(0.55, 0.55, 0.55) if y % 4 == 0 else Color.WHITE)
	return img


static func _draw_cell(img: Image, cell: String, shade: Callable) -> void:
	var c: Vector2i = CELLS[cell]
	for y in range(CELL):
		for x in range(CELL):
			img.set_pixel(c.x * CELL + x, c.y * CELL + y, shade.call(x, y))
