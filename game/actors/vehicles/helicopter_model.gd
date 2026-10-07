class_name HelicopterModel
extends RefCounted
## The police helicopter's body (add-police-helicopter, shared by add-flyable-helicopter): box
## fuselage with a white stripe, glass nose, tail boom and fin, skids, a two-blade main rotor
## and a tail rotor. Its origin is on the ground under the fuselage's middle (the skids' feet),
## like the cars'; forward is -Z.

const BODY_COLOR := Color(0.12, 0.14, 0.2)
const STRIPE_COLOR := Color(0.92, 0.92, 0.95)
const GLASS_COLOR := Color(0.35, 0.5, 0.65)
const SKID_COLOR := Color(0.2, 0.2, 0.22)
const BLADE_COLOR := Color(0.15, 0.15, 0.15)
## The fuselage box (width, height, length) and its centre's height, for collision shapes.
const FUSELAGE_SIZE := Vector3(2.2, 1.6, 4.2)
const FUSELAGE_Y := 1.4
const BOOM_SIZE := Vector3(0.4, 0.4, 4.5)
const BOOM_CENTRE := Vector3(0, 1.7, 4.3)
const ROTOR_Y := 2.45
const ROTOR_DIAMETER_M := 9.0


## Adds the meshes to `parent`; returns {"rotor": Node3D, "tail_rotor": Node3D} to spin.
static func build(parent: Node3D) -> Dictionary:
	var body := box(FUSELAGE_SIZE, BODY_COLOR)
	body.position = Vector3(0, FUSELAGE_Y, 0)
	parent.add_child(body)
	var stripe := box(Vector3(2.25, 0.25, 3.0), STRIPE_COLOR)
	stripe.position = Vector3(0, 1.3, 0.2)
	parent.add_child(stripe)
	var glass := box(Vector3(1.9, 0.9, 1.2), GLASS_COLOR)
	glass.position = Vector3(0, 1.75, -1.9)
	parent.add_child(glass)
	var boom := box(BOOM_SIZE, BODY_COLOR)
	boom.position = BOOM_CENTRE
	parent.add_child(boom)
	var fin := box(Vector3(0.12, 1.2, 0.8), BODY_COLOR)
	fin.position = Vector3(0, 2.3, 6.4)
	parent.add_child(fin)
	for side: float in [-1.0, 1.0]:
		var skid := box(Vector3(0.12, 0.12, 3.6), SKID_COLOR)
		skid.position = Vector3(side * 1.0, 0.1, 0)
		parent.add_child(skid)
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	rotor.position = Vector3(0, ROTOR_Y, 0)
	parent.add_child(rotor)
	for a in [0.0, PI * 0.5]:
		var blade := box(Vector3(0.3, 0.05, ROTOR_DIAMETER_M), BLADE_COLOR)
		blade.rotation.y = a
		rotor.add_child(blade)
	var tail_rotor := Node3D.new()
	tail_rotor.name = "TailRotor"
	tail_rotor.position = Vector3(0.25, 2.3, 6.4)
	parent.add_child(tail_rotor)
	tail_rotor.add_child(box(Vector3(0.05, 1.4, 0.18), BLADE_COLOR))
	return {"rotor": rotor, "tail_rotor": tail_rotor}


## A box mesh of `size` in `color`.
static func box(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	m.material_override = mat
	return m
