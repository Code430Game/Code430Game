class_name CharacterRig
extends Node3D
## A walking body: Skeleton3D with the CharacterMesh bones and a skinned mesh, posed by a
## procedural walk cycle. `advance(delta, speed)` drives it from movement; the stride phase
## follows distance so feet do not slide.

const STRIDE_M := 1.3  # metres per full cycle
const BLEND_RATE := 6.0  # how fast the walk amount follows the speed

var profile: Dictionary = {}
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var phase: float = 0.0
var amount: float = 0.0
## Bone name -> Quaternion that replaces the walk pose on that bone, blended in by
## `override_weight` (a held weapon's aim and swing poses the weapon arm).
var bone_override: Dictionary = {}
var override_weight: float = 0.0
## The same for the legs, blended by its own weight (a kick, add-unarmed-combat), so a leg
## move and an arm pose can run together.
var leg_override: Dictionary = {}
var leg_weight: float = 0.0


func _ready() -> void:
	if skeleton == null:
		apply_profile(profile)


func apply_profile(p: Dictionary) -> void:
	profile = CharacterProfile.normalise(p)
	if skeleton != null:
		skeleton.queue_free()
	skeleton = Skeleton3D.new()
	for i in range(CharacterMesh.BONES.size()):
		skeleton.add_bone(CharacterMesh.BONES[i][0])
	for i in range(CharacterMesh.BONES.size()):
		var parent := CharacterMesh.bone_index(CharacterMesh.BONES[i][1])
		skeleton.set_bone_parent(i, parent)
		var parent_pivot := CharacterMesh.bone_pivot(parent, profile) if parent >= 0 else Vector3.ZERO
		skeleton.set_bone_rest(i, Transform3D(Basis(), CharacterMesh.bone_pivot(i, profile) - parent_pivot))
	skeleton.reset_bone_poses()
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = CharacterMesh.build(profile, {}, true)
	mesh_instance.skin = CharacterMesh.skin_for(profile)
	skeleton.add_child(mesh_instance)
	add_child(skeleton)
	mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)  # the default path is empty: no skin without it
	_pose()


## Steps the walk cycle: `speed` in m/s along the ground.
func advance(delta: float, speed: float) -> void:
	var w := step_walk(phase, amount, delta, speed)
	phase = w.x
	amount = w.y
	_pose()


## One step of the walk cycle: returns (phase, amount) after `delta` at `speed` m/s. Shared
## with pedestrians, whose cycle runs in a shader.
static func step_walk(phase_in: float, amount_in: float, delta: float, speed: float) -> Vector2:
	var target := clampf(speed / 1.2, 0.0, 1.0)
	var a := move_toward(amount_in, target, BLEND_RATE * delta)
	var p := phase_in
	if speed > 0.05:
		p = fmod(p + TAU * speed * delta / STRIDE_M, TAU)
	elif a < 0.02:
		p = 0.0
	return Vector2(p, a)


## Re-applies the pose (after changing `bone_override`) without stepping the walk.
func repose() -> void:
	_pose()


## Sets the pose directly (previews and tests).
func set_walk(p: float, a: float) -> void:
	phase = p
	amount = a
	_pose()


func _pose() -> void:
	if skeleton == null:
		return
	var pose := CharacterMesh.walk_pose(phase, amount)
	for i in range(CharacterMesh.BONES.size()):
		var name: String = CharacterMesh.BONES[i][0]
		var q := Quaternion(Vector3.RIGHT, float(pose.get(name, 0.0)))
		if override_weight > 0.0 and bone_override.has(name):
			q = q.slerp(bone_override[name], clampf(override_weight, 0.0, 1.0))
		if leg_weight > 0.0 and leg_override.has(name):
			q = q.slerp(leg_override[name], clampf(leg_weight, 0.0, 1.0))
		skeleton.set_bone_pose_rotation(i, q)
	var hips := CharacterMesh.bone_index("hips")
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_rest(hips).origin + Vector3(0.0, float(pose.get("hips_bob", 0.0)), 0.0))
