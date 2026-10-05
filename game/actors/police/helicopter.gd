class_name PoliceHelicopter
extends Node3D
## The police helicopter (add-police-helicopter). It lifts off from its helipad (or arrives
## high from the district edge), climbs to CRUISE_M, flies to the player and circles at
## ORBIT_M, and keeps the police watching for as long as it can see them: anything solid
## between it and the player (a bridge deck, a garage ceiling, a building) hides them. At
## night a searchlight follows the player. Told to go home, it flies back and lands, then
## reports `landed` so the manager can free it.

signal landed

enum State { TAKEOFF, CHASE, RETURN }

const CRUISE_M := 55.0
const ORBIT_M := 38.0
const ORBIT_RAD_S := 0.35
const SPEED_MPS := 45.0
const CLIMB_MPS := 9.0
const BODY_COLOR := Color(0.12, 0.14, 0.2)
const STRIPE_COLOR := Color(0.92, 0.92, 0.95)

var target: Node3D
var home: Vector3
var state: int = State.TAKEOFF
var night: float = 0.0  # 0 day .. 1 night, set by the manager each frame
var _angle: float = 0.0
var _rotor: Node3D
var _tail_rotor: Node3D
var _light: SpotLight3D
var _sees: bool = false
var _beam: MeshInstance3D
var _strobes: Array[MeshInstance3D] = []
var _strobe_t: float = 0.0


func _ready() -> void:
	_build()


## True when nothing solid stands between the helicopter and its target.
func sees_target() -> bool:
	return _sees and state == State.CHASE


func go_home() -> void:
	if state != State.RETURN:
		state = State.RETURN


func _physics_process(delta: float) -> void:
	_rotor.rotate_y(delta * 28.0)
	_tail_rotor.rotate_x(delta * 40.0)
	match state:
		State.TAKEOFF:
			global_position.y += CLIMB_MPS * delta
			if global_position.y >= home.y + CRUISE_M * 0.6:
				state = State.CHASE
		State.CHASE:
			if target == null:
				go_home()
				return
			_angle += ORBIT_RAD_S * delta
			var t := target.global_position
			var goal := t + Vector3(cos(_angle) * ORBIT_M, CRUISE_M, sin(_angle) * ORBIT_M)
			_fly_to(goal, delta)
			_face(t)
			_sees = _clear_line(t)
		State.RETURN:
			var above := home + Vector3.UP * CRUISE_M * 0.6
			if Vector2(global_position.x - home.x, global_position.z - home.z).length() > 3.0:
				_fly_to(above, delta)
				_face(above)
			else:
				global_position.y -= CLIMB_MPS * delta
				if global_position.y <= home.y + 0.3:
					landed.emit()
	_update_light()


func _fly_to(goal: Vector3, delta: float) -> void:
	var to := goal - global_position
	var step := SPEED_MPS * delta
	global_position += to.normalized() * minf(step, to.length())


func _face(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) > 0.5:
		look_at(flat, Vector3.UP)
		rotate_object_local(Vector3.RIGHT, -0.12)  # nose down in forward flight


func _clear_line(t: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, t + Vector3.UP * 1.0)
	var exclude: Array[RID] = []
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	for i in range(4):
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		if hit["collider"] is StaticBody3D:
			return false  # a deck, a ceiling, a building: hidden
		exclude.append(hit["rid"])
	return true


func _update_light() -> void:
	_light.visible = night > 0.3 and state == State.CHASE and target != null
	_beam.visible = _light.visible
	if _light.visible:
		var t := target.global_position
		_light.look_at(t, Vector3.UP)
		# A faint cone down to the player: no fog on the deck preset to show the beam itself.
		var from := _light.global_position
		var length := from.distance_to(t)
		var up := (from - t).normalized()  # the cylinder's narrow top sits at the lamp
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		_beam.global_transform = Transform3D(Basis(side, up, side.cross(up)), (from + t) * 0.5)
		(_beam.mesh as CylinderMesh).height = length
		(_beam.mesh as CylinderMesh).bottom_radius = length * tan(deg_to_rad(_light.spot_angle)) * 0.9
	_strobe_t += get_physics_process_delta_time()
	var on := fmod(_strobe_t * 2.0, 1.0) < 0.15
	for i in range(_strobes.size()):
		_strobes[i].visible = on if i < 2 else true


func _build() -> void:
	var body := _box(Vector3(2.2, 1.6, 4.2), BODY_COLOR)
	body.position = Vector3(0, 1.4, 0)
	add_child(body)
	var stripe := _box(Vector3(2.25, 0.25, 3.0), STRIPE_COLOR)
	stripe.position = Vector3(0, 1.3, 0.2)
	add_child(stripe)
	var glass := _box(Vector3(1.9, 0.9, 1.2), Color(0.35, 0.5, 0.65))
	glass.position = Vector3(0, 1.75, -1.9)
	add_child(glass)
	var boom := _box(Vector3(0.4, 0.4, 4.5), BODY_COLOR)
	boom.position = Vector3(0, 1.7, 4.3)
	add_child(boom)
	var fin := _box(Vector3(0.12, 1.2, 0.8), BODY_COLOR)
	fin.position = Vector3(0, 2.3, 6.4)
	add_child(fin)
	for side: float in [-1.0, 1.0]:
		var skid := _box(Vector3(0.12, 0.12, 3.6), Color(0.2, 0.2, 0.22))
		skid.position = Vector3(side * 1.0, 0.1, 0)
		add_child(skid)
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 2.45, 0)
	add_child(_rotor)
	for a in [0.0, PI * 0.5]:
		var blade := _box(Vector3(0.3, 0.05, 9.0), Color(0.15, 0.15, 0.15))
		blade.rotation.y = a
		_rotor.add_child(blade)
	_tail_rotor = Node3D.new()
	_tail_rotor.position = Vector3(0.25, 2.3, 6.4)
	add_child(_tail_rotor)
	var tblade := _box(Vector3(0.05, 1.4, 0.18), Color(0.15, 0.15, 0.15))
	_tail_rotor.add_child(tblade)
	# Belly lights so it reads at night, and the searchlight.
	for side: float in [-1.0, 1.0]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1, 0.15, 0.15) if side < 0.0 else Color(0.2, 0.4, 1.0)
		lamp.light_energy = 1.2
		lamp.omni_range = 6.0
		lamp.position = Vector3(side * 0.9, 0.6, 0)
		add_child(lamp)
	for spec: Array in [[Vector3(-1.15, 1.4, 0), Color(1, 0.1, 0.1)], [Vector3(1.15, 1.4, 0), Color(0.15, 0.35, 1.0)], [Vector3(0, 2.9, 6.6), Color(1, 1, 1)]]:
		var strobe := _box(Vector3(0.18, 0.18, 0.18), spec[1])
		var mat := strobe.material_override as StandardMaterial3D
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = spec[1]
		mat.emission_energy_multiplier = 6.0
		strobe.position = spec[0]
		add_child(strobe)
		_strobes.append(strobe)
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.3
	cone.bottom_radius = 6.0
	cone.height = 50.0
	cone.radial_segments = 16
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(1.0, 0.95, 0.75, 0.04)
	_beam.material_override = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)
	_light = SpotLight3D.new()
	_light.light_energy = 12.0
	_light.spot_range = 120.0
	_light.spot_angle = 9.0
	_light.light_color = Color(1.0, 0.98, 0.9)
	_light.position = Vector3(0, 0.6, -1.5)
	_light.visible = false
	add_child(_light)


static func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	m.material_override = mat
	return m
