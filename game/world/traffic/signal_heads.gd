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
var _sign_poles: MultiMeshInstance3D
var _signs: MultiMeshInstance3D
var _sign_count: int = 0
var _approaches: Array = []  # [node id, edge id] per instance
var _signals: Signals
var _since_refresh: float = 0.0


## Places one pole and head per signalised approach, and a post with a red octagon per
## stop-controlled approach (an approach is an edge that can carry traffic into the node).
func setup(graph: RoadGraph, junctions: Dictionary, signals: Signals) -> void:
	_signals = signals
	_approaches.clear()
	var head_transforms: Array[Transform3D] = []
	var sign_transforms: Array[Transform3D] = []
	for nid in graph.sorted_node_ids():
		if graph.degree(nid) < 3:
			continue
		var signalised := signals.is_signalised(nid)
		var node: RoadGraph.RoadNode = graph.nodes[nid]
		var j: JunctionBuilder.Junction = junctions.get(nid)
		for eid in graph.incident(nid):
			var e: RoadGraph.RoadEdge = graph.edges[eid]
			var arrives: bool = e.to_node == nid or not e.oneway
			if not arrives:
				continue
			var control := graph.approach_control(e, nid)
			if signalised:
				head_transforms.append(_approach_transform(graph, node, j, e))
				_approaches.append([nid, eid])
			elif control == "stop":
				sign_transforms.append(_approach_transform(graph, node, j, e))
	_poles = _make_multimesh(_pole_mesh(), head_transforms, Vector3(0.0, POLE_HEIGHT_M * 0.5, 0.0), false)
	_heads = _make_multimesh(_head_mesh(), head_transforms, Vector3(0.0, HEAD_HEIGHT_M + 0.45, 0.0), true)
	_sign_poles = _make_multimesh(_sign_pole_mesh(), sign_transforms, Vector3(0.0, 1.1, 0.0), false)
	_signs = _make_multimesh(_sign_mesh(), sign_transforms, Vector3(0.0, 2.2, 0.0), false)
	_sign_count = sign_transforms.size()
	add_child(_poles)
	add_child(_heads)
	add_child(_sign_poles)
	add_child(_signs)
	_refresh()


## Transform at the right-hand corner of an approach, facing the cars coming in.
static func _approach_transform(graph: RoadGraph, node: RoadGraph.RoadNode, j: JunctionBuilder.Junction, e: RoadGraph.RoadEdge) -> Transform3D:
	var out_dir := graph.direction_from(e, node.id)  # from the node into the edge
	var travel := -out_dir  # how traffic approaches the node
	var right := Vector2(-travel.y, travel.x)
	var trim: float = j.trims.get(e.id, 6.0) if j != null else 6.0
	var base2 := Vector2(node.position.x, node.position.z) + out_dir * trim + right * (e.width_m * 0.5 + CORNER_OUT_M)
	var base := Vector3(base2.x, node.position.y, base2.y)
	var facing := Basis.looking_at(Vector3(out_dir.x, 0.0, out_dir.y), Vector3.UP)
	return Transform3D(facing, base)


## Number of stop signs placed.
func sign_count() -> int:
	return _sign_count


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
	# No visibility range: the range is measured to the centre of the whole multimesh's
	# bounding box, so heads vanished more than 400 m from the middle of the city.
	return mmi


static func _pole_mesh() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(0.16, POLE_HEIGHT_M, 0.16)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.26, 0.28)
	m.roughness = 0.6
	box.material = m
	return box


static var _head_material: ShaderMaterial = null
const HEAD_DAY_ENERGY := 0.8
const HEAD_NIGHT_ENERGY := 2.2


## Shared head material: the instance colour is the glow too, so lamps keep their colour at
## night (a flat emission colour made every lamp white after dusk). DayNight drives `night`.
static func head_material() -> ShaderMaterial:
	if _head_material == null:
		_head_material = ShaderMaterial.new()
		_head_material.shader = load("res://world/traffic/signal_head.gdshader")
		_head_material.set_shader_parameter("day_energy", HEAD_DAY_ENERGY)
		_head_material.set_shader_parameter("night_energy", HEAD_NIGHT_ENERGY)
		_head_material.set_shader_parameter("night", 0.0)
	return _head_material


static func _sign_pole_mesh() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 2.2, 0.08)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.5, 0.52)
	box.material = m
	return box


static func _sign_mesh() -> Mesh:
	var octagon := CylinderMesh.new()
	octagon.radial_segments = 8
	octagon.top_radius = 0.38
	octagon.bottom_radius = 0.38
	octagon.height = 0.04
	octagon.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.08, 0.08)
	m.roughness = 0.5
	octagon.material = m
	# A cylinder stands on its y axis; lay it on its side so the face points along z.
	var mesh := ArrayMesh.new()
	var arrays := octagon.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var rot := Basis(Vector3.RIGHT, PI * 0.5)
	for i in range(verts.size()):
		verts[i] = rot * verts[i]
		normals[i] = rot * normals[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, m)
	return mesh


static func _head_mesh() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(0.36, 0.9, 0.3)
	box.material = head_material()
	return box
