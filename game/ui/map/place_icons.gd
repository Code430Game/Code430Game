class_name PlaceIcons
extends RefCounted
## One icon set for the kinds of place on the maps (add-map-legend): the full map's markers and
## legend and the minimap's markers all draw from it. Kinds, names, colours and sizes come from
## place_icons.json; icons are white SVGs in ui/map/icons/places/ drawn on a disc of the kind's
## colour. An unknown kind gets the `missing` icon, a grey disc and its id as its name.

const DATA_PATH := "res://ui/map/place_icons.json"
const ICON_DIR := "res://ui/map/icons/places"
const UNKNOWN_COLOR := Color(0.55, 0.57, 0.62)
const OUTLINE := Color(0.05, 0.06, 0.08, 0.85)

static var _data: Dictionary = {}
static var _textures: Dictionary = {}  # icon name -> Texture2D or null


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"kinds": []}
	return _data


## A number from place_icons.json, or `fallback`.
static func num(key: String, fallback: float) -> float:
	return float(data().get(key, fallback))


## Every kind the maps know, in the legend's order.
static func kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for k: Dictionary in data().get("kinds", []):
		out.append(str(k["kind"]))
	return out


static func _entry(kind: String) -> Dictionary:
	for k: Dictionary in data().get("kinds", []):
		if str(k["kind"]) == kind:
			return k
	return {}


## The name the legend shows for `kind` ("Police"), or the id with spaces for an unknown one.
static func label(kind: String) -> String:
	var e := _entry(kind)
	return str(e["name"]) if not e.is_empty() else kind.replace("_", " ").capitalize()


## The marker colour of `kind`.
static func color(kind: String) -> Color:
	var e := _entry(kind)
	return Color.html(str(e["color"])) if not e.is_empty() else UNKNOWN_COLOR


## The icon name `kind` draws ("missing" when it has none or its file is gone).
static func icon_name(kind: String) -> String:
	var e := _entry(kind)
	var n := str(e.get("icon", "")) if not e.is_empty() else ""
	return n if n != "" and _load(n) != null else "missing"


## The legend's second line for `kind`'s places when the kind names them by title ("Underground
## · heli cover"), or "".
static func note(kind: String) -> String:
	return str(_entry(kind).get("note", ""))


## `street` shortened the way a sign would: "Kent Street" -> "Kent St", "Laurier Avenue West"
## -> "Laurier Ave W". Only a trailing suffix (and a direction after it) is shortened, so French
## names ("Rue Kent") stay as they are.
static func abbreviate(street: String) -> String:
	var words := street.strip_edges().split(" ", false)
	if words.is_empty():
		return street.strip_edges()
	var suffixes: Dictionary = data().get("street_suffixes", {})
	var directions: Dictionary = data().get("street_directions", {})
	var last := words.size() - 1
	if words.size() >= 3 and directions.has(words[last]) and suffixes.has(words[last - 1]):
		words[last - 1] = str(suffixes[words[last - 1]])
		words[last] = str(directions[words[last]])
	elif words.size() >= 2 and suffixes.has(words[last]):
		words[last] = str(suffixes[words[last]])
	return " ".join(words)


## `street` without its suffix and direction, for a short mention: "Laurier Avenue West" ->
## "Laurier", "Slater Street" -> "Slater". A name that is only a suffix stays as it is.
static func bare(street: String) -> String:
	var words := street.strip_edges().split(" ", false)
	var suffixes: Dictionary = data().get("street_suffixes", {})
	var directions: Dictionary = data().get("street_directions", {})
	if words.size() >= 3 and directions.has(words[words.size() - 1]) and suffixes.has(words[words.size() - 2]):
		words.resize(words.size() - 2)
	elif words.size() >= 2 and suffixes.has(words[words.size() - 1]):
		words.resize(words.size() - 1)
	return " ".join(words)


## Sets `title` on every place whose kind has a title template ("{street} Parking"), from its
## nearest street. Two with the same title get their cross street by `cross_format` ("Kent St
## Parking (Slater)"); any still alike are numbered in id order ("... 2"). Places of other kinds
## keep "".
static func assign_titles(places: Array) -> void:
	var sorted := places.duplicate()
	sorted.sort_custom(func(a: Services.Place, b: Services.Place) -> bool: return a.id < b.id)
	var titled: Array = []
	for p: Services.Place in sorted:
		var template := str(_entry(p.kind).get("title", ""))
		if template == "":
			p.title = ""
			continue
		p.title = template.format({"street": abbreviate(p.street)}) if p.street != "" else label(p.kind)
		titled.append(p)
	var cross_format := str(data().get("cross_format", "{title} ({cross})"))
	for p: Services.Place in _alike(titled):
		if p.cross != "":
			p.title = cross_format.format({"title": p.title, "cross": bare(p.cross)})
	var seen: Dictionary = {}
	for p: Services.Place in titled:
		var n := int(seen.get(p.title, 0)) + 1
		seen[p.title] = n
		if n > 1:
			p.title += " %d" % n


## The places of `titled` whose title another one shares.
static func _alike(titled: Array) -> Array:
	var count: Dictionary = {}
	for p: Services.Place in titled:
		count[p.title] = int(count.get(p.title, 0)) + 1
	return titled.filter(func(p: Services.Place) -> bool: return int(count[p.title]) > 1)


## The name the maps show for `place`: its title, else its name, else its kind's name.
static func display_name(place: Services.Place) -> String:
	if place.title != "":
		return place.title
	return place.name if place.name != "" else label(place.kind)


## The white icon texture for `kind`.
static func texture(kind: String) -> Texture2D:
	return _load(icon_name(kind))


## Draws `kind`'s marker centred on `at` into `ci`: an outlined disc of its colour with the
## white icon on it.
static func draw(ci: CanvasItem, at: Vector2, kind: String, radius: float) -> void:
	ci.draw_circle(at, radius + 1.5, OUTLINE)
	ci.draw_circle(at, radius, color(kind))
	var t := texture(kind)
	if t != null:
		var s := radius * 1.3
		ci.draw_texture_rect(t, Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)), false)


static func _load(n: String) -> Texture2D:
	if _textures.has(n):
		return _textures[n]
	var path := ICON_DIR.path_join(n + ".svg")
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[n] = t
	return t
