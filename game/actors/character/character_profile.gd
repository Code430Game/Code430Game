class_name CharacterProfile
extends RefCounted
## A player's look as a plain dictionary so it travels over the network and into JSON as is.
## Colour fields are palette indices; height and build are scales about 1.0.

const FIELDS: PackedStringArray = ["skin", "hair", "hair_colour", "top", "bottom", "shoes", "hat", "height", "build", "beard", "glasses", "jacket", "jacket_colour", "body"]
## Body types (CharacterMesh.BODIES): 0 is body A (the original proportions), 1 is body B. Their
## names on screen come from strings.v0.json per tone (ContentMode.text), never from code.
const BODY_COUNT := 2
const BODY_B_HEIGHT_STEPS := 2  # body B is drawn this many height steps shorter by default

const SKIN: Array[Color] = [
	Color(0.96, 0.82, 0.70), Color(0.88, 0.70, 0.55), Color(0.78, 0.58, 0.42),
	Color(0.62, 0.44, 0.30), Color(0.46, 0.31, 0.21), Color(0.32, 0.22, 0.15),
]
const HAIR_COLOUR: Array[Color] = [
	Color(0.10, 0.08, 0.07), Color(0.35, 0.22, 0.12), Color(0.60, 0.40, 0.20),
	Color(0.85, 0.72, 0.40), Color(0.65, 0.25, 0.12), Color(0.80, 0.80, 0.80),
]
const CLOTH: Array[Color] = [
	Color(0.80, 0.20, 0.18), Color(0.20, 0.42, 0.85), Color(0.22, 0.60, 0.30),
	Color(0.92, 0.78, 0.20), Color(0.92, 0.92, 0.90), Color(0.12, 0.12, 0.14),
	Color(0.45, 0.45, 0.48), Color(0.95, 0.50, 0.15), Color(0.55, 0.30, 0.75), Color(0.20, 0.65, 0.65),
]
const CLOTH_NAMES: PackedStringArray = ["red", "blue", "green", "yellow", "white", "black", "grey", "orange", "purple", "teal"]
const HAIR_NAMES: PackedStringArray = ["bald", "short", "long", "bun", "mohawk", "ponytail"]
const BEARD_NAMES: PackedStringArray = ["none", "stubble", "full"]
const GLASSES_NAMES: PackedStringArray = ["none", "glasses"]
const JACKET_NAMES: PackedStringArray = ["none", "jacket"]
const HAIR_COLOUR_NAMES: PackedStringArray = ["black", "brown", "chestnut", "blonde", "red", "silver"]
const HAT_NAMES: PackedStringArray = ["none", "cap", "beanie"]
const SHOE_COLOURS: Array[Color] = [Color(0.12, 0.10, 0.09), Color(0.92, 0.92, 0.90), Color(0.45, 0.28, 0.16), Color(0.80, 0.20, 0.18)]
const SHOE_NAMES: PackedStringArray = ["black", "white", "brown", "red"]

const HEIGHT_MIN := 0.90
const HEIGHT_MAX := 1.10
const HEIGHT_STEP := 0.02
const BUILD_MIN := 0.85
const BUILD_MAX := 1.20
const BUILD_STEP := 0.05

## Palette key -> the profile fields that index it.
const PALETTE_FIELDS := {"skin": ["skin"], "hair_colour": ["hair_colour"], "cloth": ["top", "bottom", "jacket_colour"], "shoes": ["shoes"]}

## Palettes in use: the enabled character pack's (PackLoader.items("palettes"), the first
## pack's file wins) over the built-in constants. Cached until `refresh_palettes`.
static var _palettes: Dictionary = {}  # key -> Array[Color]
static var _palette_names: Dictionary = {}  # key -> PackedStringArray
static var _palettes_loaded: bool = false
static var _palette_source: String = ""  # "pack_id:path" or "" for built-in


## The colours of a palette ("skin", "hair_colour", "cloth", "shoes") in use right now.
static func palette(key: String) -> Array[Color]:
	_ensure_palettes()
	var out: Array[Color] = []
	out.assign(_palettes.get(key, []))
	return out


## The names of a palette's entries, parallel to `palette(key)`.
static func palette_names(key: String) -> PackedStringArray:
	_ensure_palettes()
	return _palette_names.get(key, PackedStringArray())


## Where the palettes came from: "pack_id:path", or "" for the built-in colours.
static func palette_source() -> String:
	_ensure_palettes()
	return _palette_source


## Re-reads the palettes from the loader (after a pack reload or a mode change).
static func refresh_palettes() -> void:
	_palettes_loaded = false
	_ensure_palettes()


static func _ensure_palettes() -> void:
	if _palettes_loaded:
		return
	_palettes_loaded = true
	_palettes = {"skin": SKIN, "hair_colour": HAIR_COLOUR, "cloth": CLOTH, "shoes": SHOE_COLOURS}
	_palette_names = {
		"skin": _tone_names(SKIN.size()), "hair_colour": HAIR_COLOUR_NAMES, "cloth": CLOTH_NAMES, "shoes": SHOE_NAMES,
	}
	_palette_source = ""
	var loader: Node = Engine.get_main_loop().root.get_node_or_null("PackLoader") if Engine.get_main_loop() is SceneTree else null
	if loader == null:
		return
	var files: Array = loader.call("items", "palettes")
	if files.is_empty():
		return
	var file: Dictionary = files[0]
	var lists: Dictionary = file.get("palettes", {})
	var colours := {}
	var names := {}
	for key: String in PALETTE_FIELDS:
		var entries: Array = lists.get(key, [])
		if entries.is_empty():
			return  # a pack palette must be complete; keep the built-ins
		var cs: Array[Color] = []
		var ns := PackedStringArray()
		for e: Variant in entries:
			if not (e is Dictionary):
				continue
			var c: Array = (e as Dictionary).get("colour", [])
			if c.size() < 3:
				continue
			cs.append(Color(float(c[0]), float(c[1]), float(c[2])))
			ns.append(str((e as Dictionary).get("name", "")))
		colours[key] = cs
		names[key] = ns
	_palettes = colours
	_palette_names = names
	_palette_source = str(file.get("source", ""))


static func _tone_names(n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(n):
		out.append("tone %d" % (i + 1))
	return out


static func random(rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var p := normalise({
		"skin": rng.randi_range(0, _count("skin") - 1),
		"hair": rng.randi_range(0, HAIR_NAMES.size() - 1),
		"hair_colour": rng.randi_range(0, _count("hair_colour") - 1),
		"top": rng.randi_range(0, _count("top") - 1),
		"bottom": rng.randi_range(0, _count("bottom") - 1),
		"shoes": rng.randi_range(0, _count("shoes") - 1),
		"hat": 0 if rng.randf() < 0.7 else rng.randi_range(1, HAT_NAMES.size() - 1),
		"beard": 0 if rng.randf() < 0.55 else rng.randi_range(1, BEARD_NAMES.size() - 1),
		"glasses": 1 if rng.randf() < 0.2 else 0,
		"jacket": 1 if rng.randf() < 0.4 else 0,
		"jacket_colour": rng.randi_range(0, _count("jacket_colour") - 1),
		"height": HEIGHT_MIN + HEIGHT_STEP * rng.randi_range(0, _steps("height")),
		"build": BUILD_MIN + BUILD_STEP * rng.randi_range(0, _steps("build")),
	})
	# Drawn last, so every field above keeps the value it always had for a given seed.
	p["body"] = 0 if rng.randf() < body_a_share() else 1
	if p["body"] == 1:
		p["height"] = snappedf(clampf(float(p["height"]) - HEIGHT_STEP * BODY_B_HEIGHT_STEPS, HEIGHT_MIN, HEIGHT_MAX), HEIGHT_STEP)
	return p


const POPULATION_PATH := "res://core/content/population.v0.json"
static var _population: Dictionary = {}


## The share of adults with body A (population.v0.json), 0.5 when the file says nothing.
static func body_a_share() -> float:
	if _population.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POPULATION_PATH))
		_population = parsed if parsed is Dictionary else {"body": {}}
	var split: Dictionary = _population.get("body", {})
	var a := float(split.get("a", 0.5))
	var b := float(split.get("b", 0.5))
	return a / maxf(a + b, 0.0001)


## Fills missing fields and clamps every value into range; unknown keys are dropped.
static func normalise(p: Dictionary) -> Dictionary:
	var out := {}
	for key: String in FIELDS:
		var v: Variant = p.get(key, 0)
		match key:
			"height":
				out[key] = snappedf(clampf(float(v) if v is float or v is int else 1.0, HEIGHT_MIN, HEIGHT_MAX), HEIGHT_STEP)
			"build":
				out[key] = snappedf(clampf(float(v) if v is float or v is int else 1.0, BUILD_MIN, BUILD_MAX), BUILD_STEP)
			_:
				out[key] = clampi(int(v) if v is int or v is float else 0, 0, _count(key) - 1)
	return out


## The profile with one field moved `delta` steps, wrapping for choices and clamping for scales.
static func step(p: Dictionary, key: String, delta: int) -> Dictionary:
	var out := normalise(p)
	match key:
		"height":
			out[key] = snappedf(clampf(float(out[key]) + HEIGHT_STEP * delta, HEIGHT_MIN, HEIGHT_MAX), HEIGHT_STEP)
		"build":
			out[key] = snappedf(clampf(float(out[key]) + BUILD_STEP * delta, BUILD_MIN, BUILD_MAX), BUILD_STEP)
		_:
			var n := _count(key)
			out[key] = posmod(int(out[key]) + delta, n)
	return out


## Readable value for the creator's rows.
static func label(p: Dictionary, key: String) -> String:
	var v: Variant = p.get(key, 0)
	match key:
		"skin":
			return _palette_label("skin", int(v))
		"hair":
			return HAIR_NAMES[clampi(int(v), 0, HAIR_NAMES.size() - 1)]
		"hair_colour":
			return _palette_label("hair_colour", int(v))
		"top", "bottom", "jacket_colour":
			return _palette_label("cloth", int(v))
		"beard":
			return BEARD_NAMES[clampi(int(v), 0, BEARD_NAMES.size() - 1)]
		"glasses":
			return GLASSES_NAMES[clampi(int(v), 0, GLASSES_NAMES.size() - 1)]
		"jacket":
			return JACKET_NAMES[clampi(int(v), 0, JACKET_NAMES.size() - 1)]
		"shoes":
			return _palette_label("shoes", int(v))
		"hat":
			return HAT_NAMES[clampi(int(v), 0, HAT_NAMES.size() - 1)]
		"height":
			return "%d cm" % roundi(180.0 * float(v))
		"body":
			return ContentMode.text("body.a" if int(v) == 0 else "body.b")
		"build":
			return "%d%%" % roundi(100.0 * float(v))
	return str(v)


static func equals(a: Dictionary, b: Dictionary) -> bool:
	var na := normalise(a)
	var nb := normalise(b)
	for key: String in FIELDS:
		if key == "height" or key == "build":
			if not is_equal_approx(float(na[key]), float(nb[key])):
				return false
		elif int(na[key]) != int(nb[key]):
			return false
	return true


static func _palette_label(key: String, index: int) -> String:
	var names := palette_names(key)
	if names.is_empty():
		return str(index)
	return names[clampi(index, 0, names.size() - 1)]


static func _count(key: String) -> int:
	match key:
		"skin":
			return palette("skin").size()
		"hair":
			return HAIR_NAMES.size()
		"hair_colour":
			return palette("hair_colour").size()
		"top", "bottom", "jacket_colour":
			return palette("cloth").size()
		"beard":
			return BEARD_NAMES.size()
		"glasses":
			return GLASSES_NAMES.size()
		"jacket":
			return JACKET_NAMES.size()
		"shoes":
			return palette("shoes").size()
		"hat":
			return HAT_NAMES.size()
		"body":
			return BODY_COUNT
	return 1


static func _steps(key: String) -> int:
	if key == "height":
		return roundi((HEIGHT_MAX - HEIGHT_MIN) / HEIGHT_STEP)
	return roundi((BUILD_MAX - BUILD_MIN) / BUILD_STEP)
