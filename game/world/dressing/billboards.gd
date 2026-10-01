class_name Billboards
extends Node3D
## Billboards along the bigger roads showing ads from the active pack's ad pool. The ad on a
## board is deterministic per board id and session seed; the variant shown follows the tone
## mode (ContentMode.pick_variant) and refreshes when the mode changes. Posts and panels are
## two MultiMeshes; the text is a Label3D per board, visible only up close.

const CLASSES: PackedStringArray = ["trunk", "primary", "secondary"]
const SPACING_M := 220.0
const FIRST_AT_M := 60.0
const SIDE_OFFSET_M := 3.5  # beyond the road's half width
const POST_H_M := 4.0
const PANEL_W_M := 6.0
const PANEL_H_M := 3.0
const PANEL_T_M := 0.2
const TEXT_RANGE_M := 160.0
const BLANK_COLOR := Color(0.42, 0.42, 0.40)

var ads: Array = []
var session_seed: int = 0
var sites: Array[Dictionary] = []  # {"id", "transform", "ad"}

var _posts: MultiMeshInstance3D
var _panels: MultiMeshInstance3D
var _labels: Array[Label3D] = []


func setup(edges: Array, ad_list: Array, seed_value: int) -> void:
	ads = ad_list
	session_seed = seed_value
	sites.clear()
	var sorted_edges: Array = edges.duplicate()
	sorted_edges.sort_custom(func(a: RoadGraph.RoadEdge, b: RoadGraph.RoadEdge) -> bool: return a.id < b.id)
	for e: RoadGraph.RoadEdge in sorted_edges:
		if not CLASSES.has(e.road_class) or e.polyline.size() < 2 or e.tunnel:
			continue
		var next_at := FIRST_AT_M
		var walked := 0.0
		var k := 0
		for i in range(e.polyline.size() - 1):
			var a := e.polyline[i]
			var b := e.polyline[i + 1]
			var seg := a.distance_to(b)
			while seg > 0.0 and next_at < walked + seg:
				var t := (next_at - walked) / seg
				var p := a.lerp(b, t)
				var dir := (b - a).normalized()
				var right := Vector3(-dir.z, 0.0, dir.x)
				var id := "bb.%s.%d" % [e.id, k]
				sites.append({
					"id": id,
					# Local +Z (the label's face) points against travel, toward drivers approaching the board.
					"transform": Transform3D(Basis.looking_at(dir, Vector3.UP), p + right * (e.width_m * 0.5 + SIDE_OFFSET_M)),
					"ad": ads[int(hash(id) ^ session_seed) % ads.size()] if not ads.is_empty() else {},
				})
				k += 1
				next_at += SPACING_M
			walked += seg
	_build()
	refresh()
	if not ContentMode.mode_changed.is_connected(_on_mode_changed):
		ContentMode.mode_changed.connect(_on_mode_changed)


func count() -> int:
	return sites.size()


## The variant text on each board, in site order (tests and the debug overlay).
func texts() -> PackedStringArray:
	var out := PackedStringArray()
	for l in _labels:
		out.append(l.text)
	return out


func _on_mode_changed(_id: String) -> void:
	refresh()


func refresh() -> void:
	if _panels == null:
		return
	var mm := _panels.multimesh
	for i in range(sites.size()):
		var v := ContentMode.pick_variant(sites[i]["ad"]) if not (sites[i]["ad"] as Dictionary).is_empty() else {}
		var colour := BLANK_COLOR
		var text := ""
		if not v.is_empty():
			colour = Color.html(str(v.get("colour", "#808080")))
			text = str(v.get("text", ""))
		mm.set_instance_color(i, colour)
		_labels[i].text = text
		_labels[i].modulate = Color.BLACK if colour.get_luminance() > 0.45 else Color.WHITE


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_labels.clear()
	var post := BoxMesh.new()
	post.size = Vector3(0.3, POST_H_M, 0.3)
	post.material = _material(Color(0.25, 0.25, 0.27))
	var panel := BoxMesh.new()
	panel.size = Vector3(PANEL_W_M, PANEL_H_M, PANEL_T_M)
	var pm := _material(Color.WHITE)
	pm.vertex_color_use_as_albedo = true
	panel.material = pm
	_posts = _multimesh(post, Vector3(0.0, POST_H_M * 0.5, 0.0), false)
	_panels = _multimesh(panel, Vector3(0.0, POST_H_M + PANEL_H_M * 0.5, 0.0), true)
	add_child(_posts)
	add_child(_panels)
	for s in sites:
		var l := Label3D.new()
		l.font_size = 56
		l.pixel_size = 0.008
		l.outline_size = 0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.width = PANEL_W_M / l.pixel_size - 40.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.transform = (s["transform"] as Transform3D).translated_local(Vector3(0.0, POST_H_M + PANEL_H_M * 0.5, PANEL_T_M * 0.5 + 0.02))
		l.visibility_range_end = TEXT_RANGE_M
		l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(l)
		_labels.append(l)


func _multimesh(mesh: Mesh, lift: Vector3, colors: bool) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = sites.size()
	for i in range(sites.size()):
		mm.set_instance_transform(i, (sites[i]["transform"] as Transform3D).translated_local(lift))
		if colors:
			mm.set_instance_color(i, BLANK_COLOR)
	mmi.multimesh = mm
	# No visibility range: it would measure to the centre of a city-wide bounding box and hide
	# every board once the player is far from the middle of the map. Two draw calls either way.
	return mmi


static func _material(albedo: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.8
	return m
