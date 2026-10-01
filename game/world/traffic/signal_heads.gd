class_name SignalHeads
extends Node3D
## Poles and heads at every approach of each signalised junction, drawn as two MultiMeshes.
## The head's instance colour is the approach's current light; colours refresh a few times a
## second, which is all a light needs.

const Signals := preload("res://world/traffic/signal_controller.gd")
const POLE_HEIGHT_M := 4.6
const HEAD_HEIGHT_M := 3.8
const CORNER_OUT_M := 1.0  # beyond the ribbon edge
const REFRESH_S := 0.2
const COLORS := {
	Signals.Light.GREEN: Color(0.2, 0.95, 0.35),
	Signals.Light.AMBER: Color(1.0, 0.7, 0.1),
	Signals.Light.RED: Color(1.0, 0.15, 0.1),
}

var _heads: MultiMeshInstance3D
var _poles: MultiMeshInstance3D
var _approaches: Array = []  # [node id, edge id] per instance
var _signals: Signals
var _since_refresh: float = 0.0


## Places one pole and head per approach (an edge that can carry traffic into the node).
func setup(graph: RoadGraph, junctions: Dictionary, signals: Signals) -> void:
	_signals = signals
	_approaches.clear()
	var transforms: Array[Transform3D] = []
	for nid in signals.signalised_nodes():
		var node: RoadGraph.RoadNode = graph.nodes[nid]
		var j: JunctionBuilder.Junction = junctions.get(nid)
		for eid in graph.incident(nid):
			var e: RoadGraph.RoadEdge = graph.edges[eid]
			var arrives: bool = e.to_node == nid or not e.oneway
			if not arrives:
				continue
			var out_dir := graph.direction_from(e, nid)  # from the node into the edge
			var travel := -out_dir  # how traffic approaches the node
			var right := Vector2(-travel.y, travel.x)
			var trim: float = j.trims.get(eid, 6.0) if j != null else 6.0
			var base2 := Vector2(node.position.x, node.position.z) + out_dir * trim + right * (e.width_m * 0.5 + CORNER_OUT_M)
			var base := Vector3(base2.x, node.position.y, base2.y)
			var facing := Basis.looking_at(Vector3(out_dir.x, 0.0, out_dir.y), Vector3.UP)  # head faces the approaching cars
			transforms.append(Transform3D(facing, base))
			_approaches.append([nid, eid])
	_poles = _make_multimesh(_pole_mesh(), transforms, Vector3(0.0, POLE_HEIGHT_M * 0.5, 0.0), false)
	_heads = _make_multimesh(_head_mesh(), transforms, Vector3(0.0, HEAD_HEIGHT_M + 0.45, 0.0), true)
	add_child(_poles)
	add_child(_heads)
	_refresh()


func count() -> int:
	return _approaches.size()


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh >= REFRESH_S:
		_since_refresh = 0.0
		_refresh()


func _refresh() -> void:
	if _heads == null or _signals == null:
		return
	var mm := _heads.multimesh
	for i in range(_approaches.size()):
		var a: Array = _approaches[i]
		mm.set_instance_color(i, COLORS[_signals.light(a[0], a[1])])


static func _make_multimesh(mesh: Mesh, transforms: Array[Transform3D], lift: Vector3, colors: bool) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i].translated_local(lift))
		if colors:
			mm.set_instance_color(i, Color.RED)
	mmi.multimesh = mm
	mmi.visibility_range_end = 400.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mmi


static func _pole_mesh() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(0.16, POLE_HEIGHT_M, 0.16)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.26, 0.28)
	m.roughness = 0.6
	box.material = m
	return box


static var _head_material: StandardMaterial3D = null
const HEAD_NIGHT_ENERGY := 3.0


## Shared head material; DayNight raises its emission after dusk.
static func head_material() -> StandardMaterial3D:
	if _head_material == null:
		_head_material = StandardMaterial3D.new()
		_head_material.vertex_color_use_as_albedo = true
		_head_material.emission_enabled = true
		_head_material.emission = Color(0.5, 0.5, 0.5)
		_head_material.emission_energy_multiplier = 0.8
	return _head_material


static func _head_mesh() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(0.36, 0.9, 0.3)
	box.material = head_material()
	return box
