class_name Billboards
extends Node3D
## Billboards along the bigger roads showing ads from the active pack's ad pool. The ad on a
## board is deterministic per board id and session seed; the variant shown follows the tone
## mode (ContentMode.pick_variant) and refreshes when the mode changes. Posts and panels are
## two MultiMeshes; the text is a Label3D per board, visible only up close.
##
## Placement: a site every SPACING_M along trunk, primary and secondary roads (not bridges or
## tunnels). Given `Obstacles` (`obstacles_from_pack`), each site is tried at the configured
## side offsets and shifts along the road, and the first spot whose post and panel stand clear
## of every road ribbon (decks above included), crossing, cycleway, junction, building, water
## and tree (trunk at the post, crown at the panel's height) wins; a site with no clear spot is
## dropped. A post may stand on a sidewalk, as sign posts do. Without obstacles every site
## stands as computed.

const CLASSES: PackedStringArray = ["trunk", "primary", "secondary"]
const SPACING_M := 220.0
const FIRST_AT_M := 60.0
const SIDE_OFFSET_M := 3.5  # beyond the road's half width, when placed with no obstacles
const CONFIG_PATH := "res://world/dressing/billboards_config.json"
const CELL_M := 32.0  # obstacle index cell
const MAX_CLEARANCE_M := 2.0  # ribbons are indexed this far past their edge, the largest clearance a lookup can ask for
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


## What a board must stand clear of, indexed by cell: road and path ribbons, junction
## nodes, building outlines and water triangles (x, z), and trees (trunk and crown).
class Obstacles:
	extends RefCounted
	var ribbons: Dictionary = {}  # Vector2i -> Array of [Vector2 a, Vector2 b, float half_m]
	var areas: Array[PackedVector2Array] = []
	var area_cells: Dictionary = {}  # Vector2i -> Array[int] into areas
	var junctions: Dictionary = {}  # Vector2i -> PackedVector2Array of junction node positions
	var trees: Dictionary = {}  # Vector2i -> Array of [Vector2 at, float crown_low_y, float crown_high_y, float crown_r]

	## Adds a ribbon `half_m` either side of `polyline`.
	func add_ribbon(polyline: PackedVector3Array, half_m: float, kind: String = "road") -> void:
		for i in range(polyline.size() - 1):
			var a := Vector2(polyline[i].x, polyline[i].z)
			var b := Vector2(polyline[i + 1].x, polyline[i + 1].z)
			for c in Obstacles.cells(Rect2(a, Vector2.ZERO).expand(b).grow(half_m + MAX_CLEARANCE_M)):
				if not ribbons.has(c):
					ribbons[c] = []
				ribbons[c].append([a, b, half_m, kind])

	## Adds a closed outline (a building, a water triangle).
	func add_area(outline: PackedVector2Array) -> void:
		if outline.size() < 3:
			return
		var box := Rect2(outline[0], Vector2.ZERO)
		for v in outline:
			box = box.expand(v)
		areas.append(outline)
		for c in Obstacles.cells(box):
			if not area_cells.has(c):
				area_cells[c] = []
			area_cells[c].append(areas.size() - 1)

	## Adds a junction at `at`.
	func add_junction(at: Vector2) -> void:
		var c := Obstacles.cell(at)
		if not junctions.has(c):
			junctions[c] = PackedVector2Array()
		junctions[c].append(at)

	## Adds a tree from a vegetation row [x, y, z, archetype, height, crown radius, ...]: its
	## crown is the band from `crown_mid - crown_half` to `crown_mid + crown_half` of its height
	## (as CanopyCover models it), `crown_r` across.
	func add_tree(row: Array, crown_mid: float, crown_half: float) -> void:
		var at := Vector2(float(row[0]), float(row[2]))
		var h := float(row[4])
		var r := float(row[5])
		var base := float(row[1])
		for c in Obstacles.cells(Rect2(at, Vector2.ZERO).grow(r + MAX_CLEARANCE_M)):
			if not trees.has(c):
				trees[c] = []
			trees[c].append([at, base + h * (crown_mid - crown_half), base + h * (crown_mid + crown_half), r])

	## "tree" when a trunk stands within `trunk_clear_m` of the post at `post`, or a crown
	## reaches within `crown_clear_m` of the panel from `a` to `b` (x, z) while overlapping its
	## height band `low_y`..`high_y`; "" otherwise.
	func tree_blocked(post: Vector2, a: Vector2, b: Vector2, low_y: float, high_y: float, trunk_clear_m: float, crown_clear_m: float) -> String:
		var seen: Dictionary = {}
		for c in Obstacles.cells(Rect2(a, Vector2.ZERO).expand(b).expand(post)):
			for item: Array in trees.get(c, []):
				var at: Vector2 = item[0]
				if seen.has(at):
					continue
				seen[at] = true
				if at.distance_to(post) < trunk_clear_m:
					return "tree"
				if float(item[2]) < low_y or float(item[1]) > high_y:
					continue  # the crown is wholly above or below the panel
				var q := Geometry2D.get_closest_point_to_segment(at, a, b)
				if q.distance_to(at) < float(item[3]) + crown_clear_m:
					return "tree"
		return ""

	## Why `p` is not clear ("road", "junction", "area"), or "" when it is: within
	## `clearance_m` of a ribbon's edge, within `junction_clear_m` of a junction, or inside an area.
	func blocked(p: Vector2, clearance_m: float, junction_clear_m: float) -> String:
		var c := Obstacles.cell(p)
		for item: Array in ribbons.get(c, []):
			var q := Geometry2D.get_closest_point_to_segment(p, item[0], item[1])
			if q.distance_to(p) < float(item[2]) + clearance_m:
				return str(item[3])
		var reach := int(ceil(junction_clear_m / CELL_M))
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				for j in junctions.get(c + Vector2i(dx, dz), PackedVector2Array()):
					if j.distance_to(p) < junction_clear_m:
						return "junction"
		for k: int in area_cells.get(c, []):
			if Geometry2D.is_point_in_polygon(p, areas[k]):
				return "area"
		return ""

	static func cell(p: Vector2) -> Vector2i:
		return Vector2i(int(floor(p.x / CELL_M)), int(floor(p.y / CELL_M)))

	static func cells(box: Rect2) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		var lo := cell(box.position)
		var hi := cell(box.end)
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				out.append(Vector2i(cx, cz))
		return out


## Everything in `pack` a board must keep off: every road ribbon (bridges included, so no
## board stands under or beside a deck), uncovered paths of the configured
## `blocking_path_kinds` (crossings and cycleways; sidewalks may carry a post), junction nodes
## where `junction_min_degree` or more roads meet, buildings, water, and every tree in the
## pack (all of them, not a preset's capped share, so a board is clear of trees on every preset
## and stands in the same place on each).
static func obstacles_from_pack(pack: MapPack) -> Obstacles:
	var cfg := config()
	var o := Obstacles.new()
	var degree: Dictionary = {}
	for eid in pack.graph.sorted_edge_ids():
		var e: RoadGraph.RoadEdge = pack.graph.edges[eid]
		o.add_ribbon(e.polyline, e.width_m * 0.5)
		for n: String in [e.from_node, e.to_node]:
			degree[n] = int(degree.get(n, 0)) + 1
	for n in pack.graph.sorted_node_ids():
		if int(degree.get(n, 0)) >= int(cfg.get("junction_min_degree", 3)):
			var at: Vector3 = (pack.graph.nodes[n] as RoadGraph.RoadNode).position
			o.add_junction(Vector2(at.x, at.z))
	var path_kinds: Array = cfg.get("blocking_path_kinds", [])
	for w in pack.graph.pedestrian:
		if not w.covered and path_kinds.has(w.kind):
			o.add_ribbon(w.polyline, w.width_m * 0.5, "path:" + w.kind)
	for b in pack.buildings:
		if not b.rings.is_empty():
			o.add_area(b.rings[0])
	for wp in pack.water_polygons:
		for t in range(0, wp.triangles.size() - 2, 3):
			o.add_area(PackedVector2Array([wp.vertices[wp.triangles[t]], wp.vertices[wp.triangles[t + 1]], wp.vertices[wp.triangles[t + 2]]]))
	var mid := float(cfg.get("crown_mid", 0.62))
	var half := float(cfg.get("crown_half_height", 0.28))
	var coords: Array = pack.vegetation_chunks.keys()
	coords.sort()
	for coord: Vector2i in coords:
		for row: Array in (pack.vegetation_chunks[coord] as Dictionary).get("trees", []):
			o.add_tree(row, mid, half)
	return o


static var _config: Dictionary = {}


## Placement tunables from billboards_config.json.
static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config = parsed if parsed is Dictionary else {"_missing": true}
	return _config


## Places a board every SPACING_M along `edges` (the first clear spot per site when
## `obstacles` are given; see `place`) and builds them.
func setup(edges: Array, ad_list: Array, seed_value: int, obstacles: Obstacles = null) -> void:
	ads = ad_list
	session_seed = seed_value
	sites.clear()
	var sorted_edges: Array = edges.duplicate()
	sorted_edges.sort_custom(func(a: RoadGraph.RoadEdge, b: RoadGraph.RoadEdge) -> bool: return a.id < b.id)
	for e: RoadGraph.RoadEdge in sorted_edges:
		if not CLASSES.has(e.road_class) or e.polyline.size() < 2 or e.tunnel or e.bridge:
			continue
		var length := 0.0
		for i in range(e.polyline.size() - 1):
			length += e.polyline[i].distance_to(e.polyline[i + 1])
		var next_at := FIRST_AT_M
		var k := 0
		while next_at < length:
			var id := "bb.%s.%d" % [e.id, k]
			var t := place(e, next_at, length, obstacles)
			if t != Transform3D():
				sites.append({
					"id": id,
					"transform": t,
					"ad": ads[int(hash(id) ^ session_seed) % ads.size()] if not ads.is_empty() else {},
				})
			k += 1
			next_at += SPACING_M
	_build()
	refresh()
	if not ContentMode.mode_changed.is_connected(_on_mode_changed):
		ContentMode.mode_changed.connect(_on_mode_changed)


## The board's transform for a site `at` metres along `e` (of `length`): the first clear spot
## among the configured side offsets and shifts, or Transform3D() when none is clear. Without
## obstacles it is the plain spot SIDE_OFFSET_M beyond the road's half width.
static func place(e: RoadGraph.RoadEdge, at: float, length: float, obstacles: Obstacles) -> Transform3D:
	if obstacles == null:
		return spot(e, at, SIDE_OFFSET_M)
	var cfg := config()
	for side: Variant in cfg.get("side_offsets_m", [SIDE_OFFSET_M]):
		for shift: Variant in cfg.get("shifts_m", [0.0]):
			var d := at + float(shift)
			if d < 0.0 or d >= length:
				continue
			var t := spot(e, d, float(side))
			if t != Transform3D() and footprint_blocked(t, obstacles) == "":
				return t
	return Transform3D()


## Why the board at `t` is blocked ("" when clear). The post keeps `clearance_m` from every
## ribbon, `junction_clear_m` from junctions and `trunk_clear_m` from tree trunks. The panel
## faces approaching drivers, so it spans across the verge (local X) POST_H_M up: its two ends
## may come up to a ribbon's edge but not over it, nor into a building or water, and no tree
## crown at the panel's height comes within `crown_clear_m` of it.
static func footprint_blocked(t: Transform3D, obstacles: Obstacles) -> String:
	var cfg := config()
	var post := Vector2(t.origin.x, t.origin.z)
	var why := obstacles.blocked(post, float(cfg.get("clearance_m", 0.75)), float(cfg.get("junction_clear_m", 20.0)))
	if why != "":
		return why
	var across := t.basis.x * (PANEL_W_M * 0.5)
	for p: Vector3 in [t.origin + across, t.origin - across]:
		why = obstacles.blocked(Vector2(p.x, p.z), 0.0, 0.0)
		if why != "":
			return why
	var a := t.origin + across
	var b := t.origin - across
	return obstacles.tree_blocked(post, Vector2(a.x, a.z), Vector2(b.x, b.z), t.origin.y + POST_H_M, t.origin.y + POST_H_M + PANEL_H_M,
		float(cfg.get("trunk_clear_m", 0.75)), float(cfg.get("crown_clear_m", 0.5)))


## The spot `at` metres along `e`, `side_m` beyond its half width on the right of travel.
## Local +Z (the label's face) points against travel, toward drivers approaching the board.
static func spot(e: RoadGraph.RoadEdge, at: float, side_m: float) -> Transform3D:
	var walked := 0.0
	for i in range(e.polyline.size() - 1):
		var a := e.polyline[i]
		var b := e.polyline[i + 1]
		var seg := a.distance_to(b)
		if seg > 0.0 and at < walked + seg:
			var p := a.lerp(b, (at - walked) / seg)
			var dir := (b - a).normalized()
			var right := Vector3(-dir.z, 0.0, dir.x)
			return Transform3D(Basis.looking_at(dir, Vector3.UP), p + right * (e.width_m * 0.5 + side_m))
		walked += seg
	return Transform3D()


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
