class_name RoadGraphDebugView
extends MeshInstance3D
## Draws the road graph as lines: edges coloured by class, junction markers,
## and arrows on one-way edges. Toggle with the `debug_graph` action.

const LINE_LIFT_M := 0.6
const ARROW_SPACING_M := 30.0
const ARROW_SIZE_M := 2.0
const JUNCTION_MARK_M := 1.5
const DEBUG_COLORS := {
	"motorway": Color(1.0, 0.2, 0.2),
	"motorway_link": Color(1.0, 0.55, 0.2),
	"trunk": Color(1.0, 0.3, 0.3),
	"trunk_link": Color(1.0, 0.6, 0.3),
	"primary": Color(1.0, 0.85, 0.2),
	"primary_link": Color(1.0, 0.9, 0.5),
	"secondary": Color(0.6, 1.0, 0.3),
	"secondary_link": Color(0.75, 1.0, 0.55),
	"tertiary": Color(0.3, 0.9, 1.0),
	"tertiary_link": Color(0.55, 0.95, 1.0),
	"unclassified": Color(0.8, 0.8, 0.8),
	"residential": Color(1.0, 1.0, 1.0),
	"living_street": Color(0.9, 0.7, 1.0),
	"service": Color(0.55, 0.55, 0.6),
	"parking": Color(0.5, 0.5, 0.55),
}

var _graph: RoadGraph


func _ready() -> void:
	visible = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	material_override = m


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_graph") and (event is InputEventKey or Input.is_action_pressed("debug_modifier")):
		visible = not visible
		get_viewport().set_input_as_handled()


## Builds the line mesh for a graph.
func set_graph(graph: RoadGraph) -> void:
	_graph = graph
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for eid in graph.sorted_edge_ids():
		var e: RoadGraph.RoadEdge = graph.edges[eid]
		var color: Color = DEBUG_COLORS.get(e.road_class, Color.MAGENTA)
		im.surface_set_color(color)
		for i in range(e.polyline.size() - 1):
			im.surface_add_vertex(e.polyline[i] + Vector3.UP * LINE_LIFT_M)
			im.surface_add_vertex(e.polyline[i + 1] + Vector3.UP * LINE_LIFT_M)
		if e.oneway:
			_arrows(im, e, color)
	im.surface_set_color(Color(0.2, 0.6, 1.0))
	for nid in graph.sorted_node_ids():
		var n: RoadGraph.RoadNode = graph.nodes[nid]
		if n.junction_type != "junction":
			continue
		var c := n.position + Vector3.UP * LINE_LIFT_M
		im.surface_add_vertex(c + Vector3(-JUNCTION_MARK_M, 0, 0))
		im.surface_add_vertex(c + Vector3(JUNCTION_MARK_M, 0, 0))
		im.surface_add_vertex(c + Vector3(0, 0, -JUNCTION_MARK_M))
		im.surface_add_vertex(c + Vector3(0, 0, JUNCTION_MARK_M))
	im.surface_end()
	mesh = im


func _arrows(im: ImmediateMesh, e: RoadGraph.RoadEdge, color: Color) -> void:
	var total := RoadGeometry.length_xz(e.polyline)
	var d := ARROW_SPACING_M * 0.5
	while d < total:
		var p := RoadGeometry.point_at(e.polyline, d) + Vector3.UP * LINE_LIFT_M
		var q := RoadGeometry.point_at(e.polyline, minf(d + 1.0, total))
		var dir := Vector3(q.x - p.x, 0.0, q.z - p.z).normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		im.surface_set_color(color)
		im.surface_add_vertex(p)
		im.surface_add_vertex(p - dir * ARROW_SIZE_M + side * ARROW_SIZE_M * 0.5)
		im.surface_add_vertex(p)
		im.surface_add_vertex(p - dir * ARROW_SIZE_M - side * ARROW_SIZE_M * 0.5)
		d += ARROW_SPACING_M
