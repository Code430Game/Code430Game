class_name WeaponIcons
extends RefCounted
## Weapon icons for the wheel and the idle tile (add-weapon-selector): one-colour SVGs in
## `ui/hud/icons/weapons/`, white so the HUD tints them, or a PNG path a pack gives. A name
## that finds nothing falls through to the next one the weapon offers; the last is `missing`.

const DIR := "res://ui/hud/icons/weapons"

static var _cache: Dictionary = {}  # name -> Texture2D or null


## The texture for the first of `names` that exists; the missing tile when none do.
static func texture(names: PackedStringArray) -> Texture2D:
	for n in names:
		var t := _load(n)
		if t != null:
			return t
	return _load("missing")


## The name of the first of `names` that exists (what `texture` shows), or "missing".
static func resolve(names: PackedStringArray) -> String:
	for n in names:
		if _load(n) != null:
			return n
	return "missing"


static func _load(n: String) -> Texture2D:
	if _cache.has(n):
		return _cache[n]
	var t: Texture2D = null
	if n.ends_with(".png"):
		if FileAccess.file_exists(n):
			var img := Image.load_from_file(n)
			if img != null and not img.is_empty():
				t = ImageTexture.create_from_image(img)
	elif n.is_valid_identifier() or n.is_valid_filename():
		var path := DIR.path_join(n + ".svg")
		if ResourceLoader.exists(path):
			t = load(path) as Texture2D
	_cache[n] = t
	return t
