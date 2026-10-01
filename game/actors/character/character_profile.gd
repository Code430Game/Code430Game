class_name CharacterProfile
extends RefCounted
## A player's look as a plain dictionary so it travels over the network and into JSON as is.
## Colour fields are palette indices; height and build are scales about 1.0.

const FIELDS: PackedStringArray = ["skin", "hair", "hair_colour", "top", "bottom", "shoes", "hat", "height", "build"]

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
const HAIR_NAMES: PackedStringArray = ["bald", "short", "long"]
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


static func random(rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return normalise({
		"skin": rng.randi_range(0, SKIN.size() - 1),
		"hair": rng.randi_range(0, HAIR_NAMES.size() - 1),
		"hair_colour": rng.randi_range(0, HAIR_COLOUR.size() - 1),
		"top": rng.randi_range(0, CLOTH.size() - 1),
		"bottom": rng.randi_range(0, CLOTH.size() - 1),
		"shoes": rng.randi_range(0, SHOE_COLOURS.size() - 1),
		"hat": 0 if rng.randf() < 0.7 else rng.randi_range(1, HAT_NAMES.size() - 1),
		"height": HEIGHT_MIN + HEIGHT_STEP * rng.randi_range(0, _steps("height")),
		"build": BUILD_MIN + BUILD_STEP * rng.randi_range(0, _steps("build")),
	})


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
			return "tone %d" % (int(v) + 1)
		"hair":
			return HAIR_NAMES[clampi(int(v), 0, HAIR_NAMES.size() - 1)]
		"hair_colour":
			return HAIR_COLOUR_NAMES[clampi(int(v), 0, HAIR_COLOUR_NAMES.size() - 1)]
		"top", "bottom":
			return CLOTH_NAMES[clampi(int(v), 0, CLOTH_NAMES.size() - 1)]
		"shoes":
			return SHOE_NAMES[clampi(int(v), 0, SHOE_NAMES.size() - 1)]
		"hat":
			return HAT_NAMES[clampi(int(v), 0, HAT_NAMES.size() - 1)]
		"height":
			return "%d cm" % roundi(180.0 * float(v))
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


static func _count(key: String) -> int:
	match key:
		"skin":
			return SKIN.size()
		"hair":
			return HAIR_NAMES.size()
		"hair_colour":
			return HAIR_COLOUR.size()
		"top", "bottom":
			return CLOTH.size()
		"shoes":
			return SHOE_COLOURS.size()
		"hat":
			return HAT_NAMES.size()
	return 1


static func _steps(key: String) -> int:
	if key == "height":
		return roundi((HEIGHT_MAX - HEIGHT_MIN) / HEIGHT_STEP)
	return roundi((BUILD_MAX - BUILD_MIN) / BUILD_STEP)
