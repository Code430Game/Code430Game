class_name MapCredits
extends RefCounted
## The map pack's data credits on screen. ODbL asks that anything shown from OpenStreetMap data
## credits "© OpenStreetMap contributors" where people see it; the pack's manifest carries that
## line and the others (elevation and so on) in `attribution`. The minimap gets the short OSM
## line underneath, the full map gets every line in its corner, where there's room to read them.

const SHORT_PX := 12
const FULL_PX := 14


## Every attribution line of a manifest, in order.
static func lines(manifest: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var a: Variant = manifest.get("attribution", [])
	if a is String:
		out.append(a)
	elif a is Array:
		for line: Variant in a:
			if str(line).strip_edges() != "":
				out.append(str(line))
	return out


## The line for under the minimap: the OpenStreetMap credit when there is one, else the first.
static func short_line(manifest: Dictionary) -> String:
	var all := lines(manifest)
	for line in all:
		if line.contains("OpenStreetMap"):
			return line
	return all[0] if not all.is_empty() else ""


## A small muted label for credits, in the menu theme's colours.
static func label(text: String, font_px: int) -> Label:
	var data := MenuTheme.load_data()
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", MenuTheme.color(data, "muted", Color(0.7, 0.72, 0.76)))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	return l
