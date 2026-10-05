class_name MapRenderer
extends RefCounted
## Renders the road graph and water into one texture, once, for the overview map and minimap.
##
## The texture covers the pack bbox at `metres_per_pixel`. Drawing happens in a
## SubViewport with a Node2D that draws polylines and polygons; after one frame the
## viewport texture is copied into an ImageTexture and the viewport is freed.
## world_to_pixel / pixel_to_world are pure so they can be tested headless.

const DEFAULT_METRES_PER_PIXEL := 2.0
const ROAD_WIDTH_PX := {"motorway": 4.0, "trunk": 4.0, "primary": 3.0, "secondary": 2.5, "tertiary": 2.0}
const DEFAULT_ROAD_WIDTH_PX := 1.5
const BACKGROUND := Color(0.09, 0.10, 0.12)
const WATER := Color(0.16, 0.32, 0.45)
const BUILDING := Color(0.20, 0.21, 0.24)
const PARKING := Color(0.25, 0.26, 0.29)  # lots: a shade lighter than buildings, under them
const GARAGE := Color(0.45, 0.62, 0.9)
const GREEN := {"park": Color(0.17, 0.27, 0.17), "garden": Color(0.17, 0.27, 0.17), "grass": Color(0.16, 0.24, 0.16), "wood": Color(0.13, 0.23, 0.14), "scrub": Color(0.16, 0.24, 0.15)}  # underground garages: a dashed outline and a P, over the buildings

var metres_per_pixel: float = DEFAULT_METRES_PER_PIXEL
var min_x: float = 0.0
var min_z: float = 0.0
var size_px: Vector2i = Vector2i.ZERO
var texture: Texture2D


## Sets the world bounds the texture covers (local metres).
func set_bounds(bounds: Vector4, mpp: float = DEFAULT_METRES_PER_PIXEL) -> void:
	metres_per_pixel = mpp
	min_x = bounds.x
	min_z = bounds.y
	size_px = Vector2i(int(ceil((bounds.z - bounds.x) / mpp)), int(ceil((bounds.w - bounds.y) / mpp)))


## World xz -> pixel coordinates in the texture.
func world_to_pixel(x: float, z: float) -> Vector2:
	return Vector2((x - min_x) / metres_per_pixel, (z - min_z) / metres_per_pixel)


## Pixel coordinates -> world xz.
func pixel_to_world(px: Vector2) -> Vector2:
	return Vector2(px.x * metres_per_pixel + min_x, px.y * metres_per_pixel + min_z)


## Width in pixels for a road class.
static func road_width_px(road_class: String) -> float:
	return ROAD_WIDTH_PX.get(road_class.replace("_link", ""), DEFAULT_ROAD_WIDTH_PX)


## Draws the map into `texture`. Must be called from a node in the tree; awaits one frame.
func render(host: Node, graph: RoadGraph, water: Array[WaterBuilder.WaterPolygon], buildings: Array[BuildingBuilder.Building] = [], lots: Array = [], green: Array = []) -> void:
	var viewport := SubViewport.new()
	viewport.size = size_px
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	var canvas := MapCanvas.new()
	canvas.renderer = self
	canvas.graph = graph
	canvas.water = water
	canvas.buildings = buildings
	canvas.lots = lots
	canvas.green = green
	viewport.add_child(canvas)
	host.add_child(viewport)
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	texture = ImageTexture.create_from_image(img)
	viewport.queue_free()


## Draws roads and water in texture pixel space.
class MapCanvas:
	extends Node2D
	var renderer: MapRenderer
	var graph: RoadGraph
	var water: Array[WaterBuilder.WaterPolygon]
	var buildings: Array[BuildingBuilder.Building] = []
	var lots: Array = []  # ParkingLotBuilder.Lot
	var green: Array = []  # {"kind", "vertices": PackedVector2Array, "triangles": PackedInt32Array}

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(renderer.size_px)), BACKGROUND)
		# Parks, grass and woods under the lots and buildings (add-vegetation 2.3).
		for area: Dictionary in green:
			var gp := PackedVector2Array()
			for v: Vector2 in area["vertices"]:
				gp.append(renderer.world_to_pixel(v.x, v.y))
			var tris: PackedInt32Array = area["triangles"]
			var col: Color = GREEN.get(area["kind"], GREEN["grass"])
			for t in range(0, tris.size() - 2, 3):
				var ga := gp[tris[t]]
				var gb := gp[tris[t + 1]]
				var gc := gp[tris[t + 2]]
				if absf((gb - ga).cross(gc - ga)) >= 0.5:
					draw_colored_polygon(PackedVector2Array([ga, gb, gc]), col)
		for lot: ParkingLotBuilder.Lot in lots:
			if lot.kind == "underground":
				continue  # drawn on top of the buildings, below
			var pts := PackedVector2Array()
			for v in lot.outer:
				pts.append(renderer.world_to_pixel(v.x, v.y))
			var idx := Geometry2D.triangulate_polygon(pts)
			for t in range(0, idx.size(), 3):
				var a := pts[idx[t]]
				var b := pts[idx[t + 1]]
				var c := pts[idx[t + 2]]
				if absf((b - a).cross(c - a)) >= 0.5:
					draw_colored_polygon(PackedVector2Array([a, b, c]), PARKING)
		for b in buildings:
			var pts := PackedVector2Array()
			for v in b.roof_vertices:
				pts.append(renderer.world_to_pixel(v.x, v.y))
			for t in range(0, b.roof_triangles.size(), 3):
				var a := pts[b.roof_triangles[t]]
				var bb := pts[b.roof_triangles[t + 1]]
				var c := pts[b.roof_triangles[t + 2]]
				if absf((bb - a).cross(c - a)) < 0.5:
					continue
				draw_colored_polygon(PackedVector2Array([a, bb, c]), BUILDING)
		for lot: ParkingLotBuilder.Lot in lots:
			if lot.kind != "underground":
				continue
			var ring := PackedVector2Array()
			for v in lot.outer:
				ring.append(renderer.world_to_pixel(v.x, v.y))
			for i in range(ring.size()):
				draw_dashed_line(ring[i], ring[(i + 1) % ring.size()], GARAGE, 1.5, 4.0)
			var centre := renderer.world_to_pixel(lot.bounds.get_center().x, lot.bounds.get_center().y)
			draw_circle(centre, 7.0, GARAGE)
			draw_string(ThemeDB.fallback_font, centre + Vector2(-4.0, 5.0), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		for w in water:
			var pts := PackedVector2Array()
			for v in w.vertices:
				pts.append(renderer.world_to_pixel(v.x, v.y))
			for t in range(0, w.triangles.size(), 3):
				var a := pts[w.triangles[t]]
				var b := pts[w.triangles[t + 1]]
				var c := pts[w.triangles[t + 2]]
				if absf((b - a).cross(c - a)) < 0.5:
					continue  # sliver triangle, would be rejected by the canvas
				draw_colored_polygon(PackedVector2Array([a, b, c]), WATER)
		for eid in graph.sorted_edge_ids():
			var e: RoadGraph.RoadEdge = graph.edges[eid]
			var pts := PackedVector2Array()
			for p in e.polyline:
				pts.append(renderer.world_to_pixel(p.x, p.z))
			var color: Color = RoadGraphDebugView.DEBUG_COLORS.get(e.road_class, Color.WHITE)
			draw_polyline(pts, color.darkened(0.25), MapRenderer.road_width_px(e.road_class), true)
