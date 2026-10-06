class_name HeldWeapon
extends Node3D
## The weapon in a character's hand (add-weapons-and-combat 2.6). A low-poly model per variant
## `model` sits on the weapon arm's forearm, and the arm takes a pose over the walk cycle:
## held forward at the waist, raised along the line of sight while aiming, a slash across the
## body with a fading trail for melee, and a kick up for each shot. Players and officers use it.
##
## Bone space: a bone's -Y runs down the arm, and a rotation about +X swings its lower end
## toward -Z, the way the body faces, so +PI/2 on the upper arm raises it straight ahead. The
## weapon arm is the one on the body's right (+X while facing -Z); its bones are named "_l".
##
## Empty hands (add-unarmed-combat): a jab on either arm with the other up in guard, and a
## front kick on the body's left leg ("_r" bones) through the rig's leg override, drawn up
## (chambered) while fire is held for it. Each move fades in and out over its own length.

const UPPER := "upper_arm_l"
const FORE := "forearm_l"
const HAND_M := 0.34  # elbow to hand along the forearm, before height scaling
const SWING_S := 0.3
const RECOIL_S := 0.14
const RECOIL_RAD := 0.35
const BLEND_RATE := 8.0  # how fast the arm takes up or lets go of the weapon pose
const TRAIL_LIFE_S := 0.16
const TRAIL_POINTS := 14
const UPPER_R := "upper_arm_r"
const FORE_R := "forearm_r"
const THIGH := "thigh_r"
const SHIN := "shin_r"
const PUNCH_S := 0.28
const KICK_S := 0.5
const GUARD_UPPER := 0.55  # fists up by the chin
const GUARD_FORE := 1.9
const JAB_UPPER := 1.45  # arm out at shoulder height ...
const JAB_FORE := 0.08  # ... and straight
const JAB_INWARD := 0.28  # toward the body's centre line, radians
const KICK_THIGH := 1.45  # thigh raised nearly level
const CHAMBER_THIGH := 1.2
const CHAMBER_SHIN := -1.7  # knee bent, foot drawn under

var rig: CharacterRig
var model_id: String = ""
var aiming: bool = false
var _attach: BoneAttachment3D
var _model: Node3D
var _muzzle: Marker3D
var _tip: Marker3D
var _swing_t: float = -1.0  # seconds into a swing, or < 0
var _recoil_t: float = -1.0
var _weight: float = 0.0
var _trail: MeshInstance3D
var _trail_pts: Array = []  # [base: Vector3, tip: Vector3, age: float]
var _trail_color := Color(1, 1, 1)
## Fire held long enough for a kick: the leg draws up and waits.
var chamber: bool = false
## Pins a move part-way ("punch" or "kick", at `hold_t` 0..1) for screenshots.
var hold_move: String = ""
var hold_t: float = 0.5
var _punch_t: float = -1.0
var _punch_side: int = 0  # 0 the weapon arm (body's right), 1 the other
var _kick_t: float = -1.0
var _chamber_w: float = 0.0


func _ready() -> void:
	_trail = MeshInstance3D.new()
	_trail.mesh = ImmediateMesh.new()
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = m
	add_child(_trail)


## Shows the model for weapon `w` (a resolved variant), or nothing for {} (empty hands).
func set_weapon(w: Dictionary) -> void:
	var id := str(w.get("model", ""))
	if id == model_id and (_model != null) == (id != ""):
		return
	model_id = id
	if _model != null:
		_model.queue_free()
		_model = null
		_muzzle = null
		_tip = null
	if id == "" or rig == null or rig.skeleton == null:
		return
	if _attach == null or not is_instance_valid(_attach):
		_attach = BoneAttachment3D.new()
		_attach.bone_name = FORE
		rig.skeleton.add_child(_attach)
	var built := build_model(id)
	_model = built["root"]
	_muzzle = built["muzzle"]
	_tip = built["tip"]
	_trail_color = built["trail"]
	var height := float(CharacterProfile.normalise(rig.profile)["height"])
	_model.position = Vector3(0.0, -HAND_M * height, 0.0)
	_attach.add_child(_model)


func has_weapon() -> bool:
	return _model != null


## A melee swing: the arm slashes across the body and the blade leaves a trail.
func swing() -> void:
	_swing_t = 0.0
	_trail_pts.clear()


## A shot: the forearm kicks up.
func recoil() -> void:
	_recoil_t = 0.0


func swinging() -> bool:
	return _swing_t >= 0.0


## A jab with arm `side` (0 the body's right, 1 the left).
func punch(side: int) -> void:
	_punch_t = 0.0
	_punch_side = side


## A front kick; it starts from the chambered leg if fire was held for it.
func kick() -> void:
	_kick_t = KICK_S * 0.3 * _chamber_w  # from as far up as the leg was drawn
	chamber = false


func punching() -> bool:
	return _punch_t >= 0.0


func kicking() -> bool:
	return _kick_t >= 0.0


## The barrel's end in world space (shots and flashes start there), or INF without a gun.
func muzzle() -> Vector3:
	return _muzzle.global_position if _muzzle != null and _model != null else Vector3.INF


func _process(delta: float) -> void:
	if rig == null:
		return
	var want := 1.0 if _model != null else 0.0
	_weight = move_toward(_weight, want, BLEND_RATE * delta)
	if _swing_t >= 0.0:
		_swing_t += delta
		if _swing_t > SWING_S:
			_swing_t = -1.0
	if _recoil_t >= 0.0:
		_recoil_t += delta
		if _recoil_t > RECOIL_S:
			_recoil_t = -1.0
	var pose := arm_pose(aiming, _swing_t / SWING_S if _swing_t >= 0.0 else -1.0, _recoil_t / RECOIL_S if _recoil_t >= 0.0 else -1.0)
	var weight := _weight
	if hold_move == "punch":
		_punch_t = hold_t * PUNCH_S
	elif hold_move == "kick":
		_kick_t = hold_t * KICK_S
	if _punch_t >= 0.0:
		_punch_t += 0.0 if hold_move != "" else delta
		if _punch_t > PUNCH_S:
			_punch_t = -1.0
	if _kick_t >= 0.0:
		_kick_t += 0.0 if hold_move != "" else delta
		if _kick_t > KICK_S:
			_kick_t = -1.0
	_chamber_w = move_toward(_chamber_w, 1.0 if chamber else 0.0, BLEND_RATE * delta)
	if _model == null:
		# Empty hands: a jab, or the guard while kicking or drawing a kick.
		var p := _punch_t / PUNCH_S if _punch_t >= 0.0 else -1.0
		var k := _kick_t / KICK_S if _kick_t >= 0.0 else -1.0
		pose = jab_pose(_punch_side, maxf(p, 0.0))
		weight = maxf(move_weight(p), maxf(move_weight(k), _chamber_w))
		rig.leg_override = kick_pose(k if k >= 0.0 else 0.3)
		rig.leg_weight = maxf(move_weight(k), _chamber_w)
	else:
		rig.leg_weight = 0.0
	rig.bone_override = pose
	rig.override_weight = weight
	rig.repose()
	_step_trail(delta)


## The weapon arm's pose: {UPPER: Quaternion, FORE: Quaternion}. `swing` and `kick` run 0..1
## through a slash or a shot (negative when not happening).
static func arm_pose(aim: bool, swing: float, kick: float) -> Dictionary:
	var upper := Quaternion(Vector3.RIGHT, 0.15)  # held: upper arm nearly at the side ...
	var fore := Quaternion(Vector3.RIGHT, 1.3)  # ... forearm forward, weapon pointing ahead and down
	if aim:
		upper = Quaternion(Vector3.RIGHT, PI * 0.5)  # straight ahead along the line of sight
		fore = Quaternion.IDENTITY
	if swing >= 0.0:
		# Wind up out to the right, then cut across to the left; the arm is raised throughout.
		var s := clampf(swing, 0.0, 1.0)
		var cut := smoothstep(0.25, 0.85, s)
		var yaw := lerpf(-1.1, 1.0, cut)  # about Y: negative swings the arm out to the right
		var lift := lerpf(1.5, 1.1, cut)  # high on the wind-up, coming down through the cut
		upper = Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, lift)
		fore = Quaternion(Vector3.RIGHT, lerpf(0.9, 0.2, cut))
	if kick >= 0.0:
		var k := (1.0 - clampf(kick, 0.0, 1.0)) * RECOIL_RAD
		fore = fore * Quaternion(Vector3.RIGHT, -k)  # muzzle up
	return {UPPER: upper, FORE: fore}


## Both arms with empty hands: arm `side` jabs (`t` 0..1 out and back) while the other stays
## up in guard. At t = 0 and 1 both arms are in guard.
static func jab_pose(side: int, t: float) -> Dictionary:
	var out := smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.5, 1.0, t))
	var out_l := out if side == 0 else 0.0
	var out_r := out if side == 1 else 0.0
	# A positive turn about Y brings the body's right arm in toward the centre; the left arm
	# turns the other way.
	return {
		UPPER: Quaternion(Vector3.UP, JAB_INWARD) * Quaternion(Vector3.RIGHT, lerpf(GUARD_UPPER, JAB_UPPER, out_l)),
		FORE: Quaternion(Vector3.RIGHT, lerpf(GUARD_FORE, JAB_FORE, out_l)),
		UPPER_R: Quaternion(Vector3.UP, -JAB_INWARD) * Quaternion(Vector3.RIGHT, lerpf(GUARD_UPPER, JAB_UPPER, out_r)),
		FORE_R: Quaternion(Vector3.RIGHT, lerpf(GUARD_FORE, JAB_FORE, out_r)),
	}


## The kicking leg over a kick (`t` 0..1): drawn up with the knee bent (0.3), snapped out
## straight at hip height (0.5 to 0.65), then back down.
static func kick_pose(t: float) -> Dictionary:
	var c := smoothstep(0.0, 0.3, t)
	var e := smoothstep(0.3, 0.5, t)
	var back := 1.0 - smoothstep(0.65, 1.0, t)
	var thigh := lerpf(lerpf(0.0, CHAMBER_THIGH, c), KICK_THIGH, e) * back
	var shin := lerpf(lerpf(0.0, CHAMBER_SHIN, c), -0.05, e) * back
	return {THIGH: Quaternion(Vector3.RIGHT, thigh), SHIN: Quaternion(Vector3.RIGHT, shin)}


## How much a move at `t` (0..1, negative when not happening) takes over the walk pose: in
## quickly, out over the last quarter.
static func move_weight(t: float) -> float:
	if t < 0.0:
		return 0.0
	return smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.8, 1.0, t))


func _step_trail(delta: float) -> void:
	for p in _trail_pts:
		p[2] += delta
	while not _trail_pts.is_empty() and float(_trail_pts[0][2]) > TRAIL_LIFE_S:
		_trail_pts.pop_front()
	if _swing_t >= 0.0 and _tip != null and _model != null:
		var base := _model.global_position
		_trail_pts.append([base.lerp(_tip.global_position, 0.35), _tip.global_position, 0.0])
		while _trail_pts.size() > TRAIL_POINTS:
			_trail_pts.pop_front()
	var im := _trail.mesh as ImmediateMesh
	im.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _trail_pts:
		var a := 1.0 - float(p[2]) / TRAIL_LIFE_S
		var c := Color(_trail_color.r, _trail_color.g, _trail_color.b, _trail_color.a * a)
		im.surface_set_color(c)
		im.surface_add_vertex(p[0])
		im.surface_set_color(c)
		im.surface_add_vertex(p[1])
	im.surface_end()


## Builds a model: {"root": Node3D, "muzzle": Marker3D or null, "tip": Marker3D or null,
## "trail": Color}. Models run along -Y from the grip (the hand); +Z is underneath when the
## arm is raised to aim, so grips hang toward +Z.
static func build_model(id: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "Weapon"
	var muzzle: Marker3D = null
	var tip: Marker3D = null
	var trail := Color(1, 1, 1, 0.5)
	match id:
		"knife":
			root.add_child(_part(Vector3(0.035, 0.11, 0.03), Vector3(0, 0.0, 0), Color(0.12, 0.1, 0.09)))  # handle
			root.add_child(_part(Vector3(0.012, 0.17, 0.035), Vector3(0, -0.14, 0.005), Color(0.82, 0.84, 0.86)))  # blade
			tip = _marker(Vector3(0, -0.23, 0))
			trail = Color(0.9, 0.92, 1.0, 0.45)
		"sabre":
			root.add_child(_part(Vector3(0.04, 0.16, 0.04), Vector3(0, 0.0, 0), Color(0.2, 0.2, 0.24)))  # hilt
			root.add_child(_part(Vector3(0.09, 0.02, 0.05), Vector3(0, -0.08, 0), Color(0.5, 0.5, 0.55)))  # guard
			root.add_child(_glow(Vector3(0.025, 0.85, 0.025), Vector3(0, -0.52, 0), Color(0.3, 0.9, 1.0), 5.0))  # blade
			tip = _marker(Vector3(0, -0.94, 0))
			trail = Color(0.35, 0.9, 1.0, 0.7)
		"brush":
			root.add_child(_part(Vector3(0.03, 0.3, 0.03), Vector3(0, -0.08, 0), Color(0.7, 0.5, 0.3)))  # handle
			root.add_child(_part(Vector3(0.07, 0.04, 0.04), Vector3(0, -0.24, 0), Color(0.75, 0.75, 0.78)))  # ferrule
			root.add_child(_part(Vector3(0.075, 0.08, 0.03), Vector3(0, -0.3, 0), Color(0.95, 0.35, 0.55)))  # bristles, paint on
			tip = _marker(Vector3(0, -0.34, 0))
			trail = Color(0.95, 0.35, 0.55, 0.6)
		"pistol":
			root.add_child(_part(Vector3(0.035, 0.2, 0.05), Vector3(0, -0.07, -0.03), Color(0.12, 0.12, 0.13)))  # slide
			root.add_child(_part(Vector3(0.032, 0.05, 0.1), Vector3(0, 0.0, 0.03), Color(0.16, 0.15, 0.15)))  # grip
			muzzle = _marker(Vector3(0, -0.18, -0.03))
		"blaster":
			root.add_child(_part(Vector3(0.05, 0.26, 0.06), Vector3(0, -0.09, -0.03), Color(0.85, 0.87, 0.9)))  # body
			root.add_child(_part(Vector3(0.04, 0.06, 0.1), Vector3(0, 0.0, 0.03), Color(0.25, 0.27, 0.3)))  # grip
			root.add_child(_glow(Vector3(0.055, 0.12, 0.015), Vector3(0, -0.1, -0.065), Color(0.3, 0.9, 1.0), 4.0))  # power cell
			root.add_child(_glow(Vector3(0.03, 0.02, 0.03), Vector3(0, -0.225, -0.03), Color(0.3, 0.9, 1.0), 6.0))  # emitter
			muzzle = _marker(Vector3(0, -0.24, -0.03))
		"paintball_gun":
			root.add_child(_part(Vector3(0.05, 0.32, 0.06), Vector3(0, -0.11, -0.03), Color(0.2, 0.55, 0.9)))  # body and barrel
			root.add_child(_part(Vector3(0.04, 0.06, 0.1), Vector3(0, 0.0, 0.03), Color(0.15, 0.15, 0.18)))  # grip
			var hopper := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.07
			sm.height = 0.12
			hopper.mesh = sm
			hopper.material_override = _mat(Color(0.95, 0.85, 0.2))
			hopper.position = Vector3(0, -0.05, -0.12)  # on top while aiming
			root.add_child(hopper)
			muzzle = _marker(Vector3(0, -0.28, -0.03))
		"net_gun":
			root.add_child(_part(Vector3(0.07, 0.22, 0.07), Vector3(0, -0.08, -0.03), Color(0.95, 0.6, 0.15)))  # body
			root.add_child(_part(Vector3(0.11, 0.06, 0.11), Vector3(0, -0.21, -0.03), Color(0.25, 0.25, 0.28)))  # net cup
			root.add_child(_part(Vector3(0.04, 0.06, 0.1), Vector3(0, 0.0, 0.03), Color(0.15, 0.15, 0.18)))  # grip
			muzzle = _marker(Vector3(0, -0.25, -0.03))
	if muzzle != null:
		root.add_child(muzzle)
	if tip != null:
		root.add_child(tip)
	return {"root": root, "muzzle": muzzle, "tip": tip, "trail": trail}


static func _part(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = _mat(color)
	m.position = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


static func _glow(size: Vector3, at: Vector3, color: Color, energy: float) -> MeshInstance3D:
	var m := _part(size, at, color)
	var mat := m.material_override as StandardMaterial3D
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return m


static func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5
	return mat


static func _marker(at: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.position = at
	return m
