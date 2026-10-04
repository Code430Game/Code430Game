class_name CharacterRagdoll
extends Node3D
## A character that falls under physics: a CharacterRig whose bones are driven by
## PhysicalBone3Ds (capsules and boxes sized from the profile, cone joints at the neck,
## shoulders, spine and hips, hinges at the elbows and knees). Knows nothing about who uses it:
## pedestrians pool them, and players or NPCs can use the same class. Callers decide when to
## fall and how hard.
##
## Use: begin(profile, transform, phase, amount, velocity) -> apply_impulse(...) any time while
## active -> settle() to hold the pose and stop simulating -> release() to hide and reuse.
## Bones sit on the pedestrian layer and only collide with layer 1 (world, vehicles), not with
## each other: overlapping limbs never explode the joints.

signal settled

const LAYER := 4  # physics layer 3, shared with walking pedestrians
const MASK := 1
const PARKED := Vector3(0.0, -1000.0, 0.0)

## Bone -> shape and mass, in model space at scale 1 (CharacterMesh units). "c" is the
## shape centre; capsules run along the bone (Y at rest). Masses add up to 75 kg.
const BODIES := {
	"hips": {"box": Vector3(0.34, 0.22, 0.22), "c": Vector3(0.0, 0.92, 0.0), "kg": 11.0},
	"spine": {"box": Vector3(0.38, 0.50, 0.22), "c": Vector3(0.0, 1.20, 0.0), "kg": 22.0},
	"head": {"sphere": 0.13, "c": Vector3(0.0, 1.64, 0.0), "kg": 6.0},
	"upper_arm_l": {"capsule": [0.06, 0.36], "c": Vector3(0.30, 1.21, 0.0), "kg": 2.5},
	"upper_arm_r": {"capsule": [0.06, 0.36], "c": Vector3(-0.30, 1.21, 0.0), "kg": 2.5},
	"forearm_l": {"capsule": [0.055, 0.40], "c": Vector3(0.30, 0.84, 0.0), "kg": 2.0},
	"forearm_r": {"capsule": [0.055, 0.40], "c": Vector3(-0.30, 0.84, 0.0), "kg": 2.0},
	"thigh_l": {"capsule": [0.085, 0.44], "c": Vector3(0.11, 0.67, 0.0), "kg": 9.0},
	"thigh_r": {"capsule": [0.085, 0.44], "c": Vector3(-0.11, 0.67, 0.0), "kg": 9.0},
	"shin_l": {"capsule": [0.07, 0.46], "c": Vector3(0.11, 0.25, 0.0), "kg": 4.5},
	"shin_r": {"capsule": [0.07, 0.46], "c": Vector3(-0.11, 0.25, 0.0), "kg": 4.5},
}
## Joint per bone (the root has none): cone [swing, twist] or hinge [lower, upper], degrees.
## Hinges bend about the bone's X axis like the walk cycle: knees back, elbows forward.
const JOINTS := {
	"spine": {"cone": [25.0, 20.0]},
	"head": {"cone": [40.0, 30.0]},
	"upper_arm_l": {"cone": [80.0, 30.0]},
	"upper_arm_r": {"cone": [80.0, 30.0]},
	"forearm_l": {"hinge": [0.0, 120.0]},
	"forearm_r": {"hinge": [0.0, 120.0]},
	"thigh_l": {"cone": [60.0, 15.0]},
	"thigh_r": {"cone": [60.0, 15.0]},
	"shin_l": {"hinge": [-120.0, 0.0]},
	"shin_r": {"hinge": [-120.0, 0.0]},
}

var rig: CharacterRig
var simulator: PhysicalBoneSimulator3D
var bones: Array[PhysicalBone3D] = []
var active: bool = false
var _settled: bool = false
var _profile: Dictionary = {}


func _ready() -> void:
	if rig == null:
		build({})
	release()


## Builds (or rebuilds) the rig and its physical bones for a profile.
func build(profile: Dictionary) -> void:
	_profile = CharacterProfile.normalise(profile)
	if rig != null:
		rig.queue_free()
	rig = CharacterRig.new()
	rig.profile = _profile
	add_child(rig)  # builds the skeleton and mesh
	var skeleton := rig.skeleton
	simulator = PhysicalBoneSimulator3D.new()
	skeleton.add_child(simulator)
	bones.clear()
	var s := Vector3(float(_profile["build"]), float(_profile["height"]), float(_profile["build"]))
	for i in range(CharacterMesh.BONES.size()):
		var name: String = CharacterMesh.BONES[i][0]
		var spec: Dictionary = BODIES[name]
		var pivot := CharacterMesh.bone_pivot(i, _profile)
		var centre := (spec["c"] as Vector3) * s
		var pb := PhysicalBone3D.new()
		pb.name = name
		pb.bone_name = name
		pb.mass = float(spec["kg"])
		pb.collision_layer = LAYER
		pb.collision_mask = MASK
		pb.friction = 0.8
		pb.linear_damp = 0.1
		pb.angular_damp = 0.8
		pb.body_offset = Transform3D(Basis(), centre - pivot)
		pb.joint_offset = Transform3D(Basis(), pivot - centre)
		var joint: Dictionary = JOINTS.get(name, {})
		if joint.has("cone"):
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", float(joint["cone"][0]))
			pb.set("joint_constraints/twist_span", float(joint["cone"][1]))
		elif joint.has("hinge"):
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			pb.joint_rotation = Vector3(0.0, PI * 0.5, 0.0)  # hinge axis (joint Z) along the bone's X
			pb.set("joint_constraints/angular_limit_enabled", true)
			pb.set("joint_constraints/angular_limit_lower", float(joint["hinge"][0]))
			pb.set("joint_constraints/angular_limit_upper", float(joint["hinge"][1]))
		else:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		var shape := CollisionShape3D.new()
		if spec.has("box"):
			var box := BoxShape3D.new()
			box.size = (spec["box"] as Vector3) * s
			shape.shape = box
		elif spec.has("sphere"):
			var sphere := SphereShape3D.new()
			sphere.radius = float(spec["sphere"]) * s.x
			shape.shape = sphere
		else:
			var capsule := CapsuleShape3D.new()
			capsule.radius = float(spec["capsule"][0]) * s.x
			capsule.height = maxf(float(spec["capsule"][1]) * s.y, capsule.radius * 2.0)
			shape.shape = capsule
		pb.add_child(shape)
		simulator.add_child(pb)
		bones.append(pb)


## Starts a fall: the body appears at `xform` in the walk pose (`phase`, `amount`) with every
## bone moving at `velocity`. Rebuilds first when the profile differs from the last one.
func begin(profile: Dictionary, xform: Transform3D, phase: float = 0.0, amount: float = 0.0, velocity: Vector3 = Vector3.ZERO) -> void:
	var p := CharacterProfile.normalise(profile)
	if p != _profile:
		build(p)
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	global_transform = xform
	rig.set_walk(phase, amount)
	simulator.active = true
	simulator.physical_bones_start_simulation()
	for pb in bones:
		pb.linear_velocity = velocity
		pb.angular_velocity = Vector3.ZERO
	active = true
	_settled = false


## Pushes the body: `impulse` (N s) at world `point`. `spread` (0..1) of it moves the whole
## body evenly; the rest lands on the bone nearest the point (a car sweeps the body along and
## takes the legs; a bullet would use spread 0 and move only what it hits).
func apply_impulse(impulse: Vector3, point: Vector3, spread: float = 0.0) -> void:
	if not active or _settled:
		return
	var total := total_mass()
	if spread > 0.0:
		for pb in bones:
			pb.linear_velocity += impulse * spread / total
	var near := nearest_bone(point)
	if near != null and spread < 1.0:
		near.apply_impulse(impulse * (1.0 - spread), point - near.global_position)


## The physical bone whose body centre is nearest a world point.
func nearest_bone(point: Vector3) -> PhysicalBone3D:
	var best: PhysicalBone3D = null
	var best_d := INF
	for pb in bones:
		var d := pb.global_position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = pb
	return best


func total_mass() -> float:
	var m := 0.0
	for pb in bones:
		m += pb.mass
	return m


## Velocity of the body's centre of mass.
func velocity() -> Vector3:
	var sum := Vector3.ZERO
	for pb in bones:
		sum += pb.linear_velocity * pb.mass
	return sum / total_mass()


## Where the body is: the hips bone's transform (for following, despawning, snapshots).
func root_transform() -> Transform3D:
	return bones[0].global_transform if not bones.is_empty() else global_transform


## Stops simulating and holds the pose the body fell into.
func settle() -> void:
	if not active or _settled:
		return
	var skeleton := rig.skeleton
	# From the physical bones themselves: the skeleton's own global poses don't include the
	# simulator's output, so holding those would stand the body back up.
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var globals: Array[Transform3D] = []
	for pb in bones:
		globals.append(to_skeleton * pb.global_transform * pb.body_offset.affine_inverse())
	simulator.physical_bones_stop_simulation()
	simulator.active = false
	for i in range(skeleton.get_bone_count()):
		var parent := skeleton.get_bone_parent(i)
		var local := globals[i] if parent < 0 else globals[parent].affine_inverse() * globals[i]
		skeleton.set_bone_pose(i, local)
	_settled = true
	settled.emit()


func is_settled() -> bool:
	return _settled


## Hides the body and takes it out of the physics world, ready for the next fall.
func release() -> void:
	if simulator != null and simulator.is_simulating_physics():
		simulator.physical_bones_stop_simulation()
	if simulator != null:
		simulator.active = false
	active = false
	_settled = false
	visible = false
	global_position = PARKED
	process_mode = Node.PROCESS_MODE_DISABLED
