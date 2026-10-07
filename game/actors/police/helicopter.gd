class_name PoliceHelicopter
extends Node3D
## The police helicopter (add-police-helicopter). It lifts off from its helipad (or arrives
## high from the district edge), climbs to `cruise_m`, flies to the player and circles at
## `orbit_m`, and keeps the police watching for as long as it can see them: anything solid
## between it and the player (a bridge deck, a garage ceiling, a building) or dense tree
## canopy (`canopy`, update-police-pursuit) hides them. At night a searchlight follows the
## player. Out of sight (under cover, or more than `sight_m` away) for `lost_s`, it circles
## where it last saw them and sweeps the light there; it picks them up again only by seeing
## them. It flies at `speed_mps`, slower than a fast car, so a player can also outrun it in
## the open. Told to go home, it flies back and lands, then reports `landed` so the manager can
## free it. Tunables come from the `helicopter` block of police_config.json (`config`).

signal landed

enum State { TAKEOFF, CHASE, SEARCH, RETURN }

## Used when police_config.json leaves a key out.
const DEFAULTS := {
	"cruise_m": 55.0,
	"orbit_m": 38.0,
	"orbit_rad_s": 0.35,
	"speed_mps": 35.0,
	"climb_mps": 9.0,
	"sight_m": 150.0,  # how far the crew can pick someone out
	"lost_s": 2.0,  # out of sight this long: off to search where they were last seen
	"search_radius_m": 70.0,
	"search_rad_s": 0.25,
	"shadow_size_m": 7.0,
	"shadow_grow_per_m": 0.008,
	"shadow_alpha": 0.7,
	"shadow_fade_from_m": 30.0,
	"shadow_fade_to_m": 160.0,
	"shadow_night_off": 0.5,
	"shadow_ray_m": 300.0,
}
const BODY_COLOR := Color(0.12, 0.14, 0.2)
const STRIPE_COLOR := Color(0.92, 0.92, 0.95)

var target: Node3D
var home: Vector3
## The `helicopter` block of police_config.json; missing keys fall back to DEFAULTS.
var config: Dictionary = {}
## Dense tree canopy that hides the target from the crew (null: trees never hide anyone).
var canopy: CanopyCover
var state: int = State.TAKEOFF
var night: float = 0.0  # 0 day .. 1 night, set by the manager each frame
var _angle: float = 0.0
var _rotor: Node3D
var _tail_rotor: Node3D
var _light: SpotLight3D
var _sees: bool = false
var last_seen: Vector3  # where the crew last had the target, the centre of a search
var _unseen_s: float = 0.0
var _beam: MeshInstance3D
var _strobes: Array[MeshInstance3D] = []
var _strobe_t: float = 0.0
var _shadow: MeshInstance3D


func _ready() -> void:
	_build()


## True when nothing solid stands between the helicopter and its target.
func sees_target() -> bool:
	return _sees and state == State.CHASE


## Circling where it lost the target.
func searching() -> bool:
	return state == State.SEARCH


## A tunable from `config`, or its default.
func tun(key: String) -> float:
	return float(config.get(key, DEFAULTS[key]))


## Ground units have the target at `pos`: a search moves there.
func tip(pos: Vector3) -> void:
	last_seen = pos


func go_home() -> void:
	if state != State.RETURN:
		state = State.RETURN


func _physics_process(delta: float) -> void:
	_rotor.rotate_y(delta * 28.0)
	_tail_rotor.rotate_x(delta * 40.0)
	match state:
		State.TAKEOFF:
			global_position.y += tun("climb_mps") * delta
			if global_position.y >= home.y + tun("cruise_m") * 0.6:
				state = State.CHASE
		State.CHASE:
			if target == null:
				go_home()
				return
			_angle += tun("orbit_rad_s") * delta
			var t := target.global_position
			_sees = _can_see(t)
			if _sees:
				last_seen = t
				_unseen_s = 0.0
			else:
				_unseen_s += delta
				if _unseen_s >= tun("lost_s"):
					state = State.SEARCH  # lost them: circle where they were
			# While it still has them (or only just lost them) it follows them.
			var centre := t if _sees else last_seen
			var goal := centre + Vector3(cos(_angle) * tun("orbit_m"), tun("cruise_m"), sin(_angle) * tun("orbit_m"))
			_fly_to(goal, delta)
			_face(centre)
		State.SEARCH:
			if target == null:
				go_home()
				return
			_angle += tun("search_rad_s") * delta
			var goal := last_seen + Vector3(cos(_angle) * tun("search_radius_m"), tun("cruise_m"), sin(_angle) * tun("search_radius_m"))
			_fly_to(goal, delta)
			_face(last_seen)
			_sees = _can_see(target.global_position)
			if _sees:
				state = State.CHASE
				last_seen = target.global_position
				_unseen_s = 0.0
		State.RETURN:
			var above := home + Vector3.UP * tun("cruise_m") * 0.6
			if Vector2(global_position.x - home.x, global_position.z - home.z).length() > 3.0:
				_fly_to(above, delta)
				_face(above)
			else:
				global_position.y -= tun("climb_mps") * delta
				if global_position.y <= home.y + 0.3:
					landed.emit()
	_update_light()
	update_shadow()


## The blob shadow under the helicopter: on the first solid ground (or deck) straight below,
## sized and faded by height (`shadow_alpha_at`), gone at night. One ray per physics frame.
func update_shadow() -> void:
	var alpha := shadow_alpha_at(-1.0, night)
	if alpha <= 0.0 or not is_inside_tree():
		_shadow.visible = false
		return
	var ground := _ground_below()
	if ground == Vector3.INF:
		_shadow.visible = false
		return
	var height := global_position.y - ground.y
	alpha = shadow_alpha_at(height, night)
	_shadow.visible = alpha > 0.0
	if not _shadow.visible:
		return
	var size := shadow_size_at(height)
	_shadow.global_transform = Transform3D(Basis.from_scale(Vector3(size, 1.0, size)), ground + Vector3.UP * 0.06)
	(_shadow.material_override as StandardMaterial3D).albedo_color.a = alpha


## The blob's opacity at `height` above the ground and `night_f` (0 day .. 1 night): full
## `shadow_alpha` up to `shadow_fade_from_m`, fading to nothing at `shadow_fade_to_m`, and scaled
## down to nothing as the night factor reaches `shadow_night_off`. A negative height checks the
## night alone.
func shadow_alpha_at(height: float, night_f: float) -> float:
	var day := clampf(1.0 - night_f / maxf(tun("shadow_night_off"), 0.001), 0.0, 1.0)
	if height < 0.0:
		return tun("shadow_alpha") * day
	var fade := 1.0 - clampf((height - tun("shadow_fade_from_m")) / maxf(tun("shadow_fade_to_m") - tun("shadow_fade_from_m"), 0.001), 0.0, 1.0)
	return tun("shadow_alpha") * day * fade


## The blob's width at `height`: the rotor's size, a little wider (and softer) the higher it is.
func shadow_size_at(height: float) -> float:
	return tun("shadow_size_m") * (1.0 + maxf(height, 0.0) * tun("shadow_grow_per_m"))


## The first static surface straight below (ground, deck, roof), or Vector3.INF.
func _ground_below() -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * tun("shadow_ray_m"))
	var exclude: Array[RID] = []
	for i in range(4):
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return Vector3.INF
		if hit["collider"] is StaticBody3D:
			return hit["position"]
		exclude.append(hit["rid"])  # a car or a person: the blob lies on the ground under them
	return Vector3.INF


func _fly_to(goal: Vector3, delta: float) -> void:
	var to := goal - global_position
	var step := tun("speed_mps") * delta
	global_position += to.normalized() * minf(step, to.length())


func _face(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) > 0.5:
		look_at(flat, Vector3.UP)
		rotate_object_local(Vector3.RIGHT, -0.12)  # nose down in forward flight


## In range, nothing solid in the way and no dense canopy over the line.
func _can_see(t: Vector3) -> bool:
	if global_position.distance_to(t) > tun("sight_m") or not _clear_line(t):
		return false
	return canopy == null or not canopy.blocks(global_position, t + Vector3.UP * 1.0)


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
	_light.visible = night > 0.3 and state in [State.CHASE, State.SEARCH] and target != null
	_beam.visible = _light.visible
	if _light.visible:
		# On them while it has them; sweeping the ground where they were while it searches.
		var t := target.global_position if _sees else last_seen + Vector3(sin(_strobe_t * 0.7) * 25.0, 0.0, cos(_strobe_t * 0.9) * 25.0)
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
	_shadow = MeshInstance3D.new()
	_shadow.name = "Shadow"
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	_shadow.mesh = quad
	var blob := GradientTexture2D.new()
	blob.fill = GradientTexture2D.FILL_RADIAL
	blob.fill_from = Vector2(0.5, 0.5)
	blob.fill_to = Vector2(1.0, 0.5)
	blob.width = 64
	blob.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.85))
	blob.gradient = g
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.02, 0.03, 0.05, tun("shadow_alpha"))
	sm.albedo_texture = blob
	sm.render_priority = 1
	_shadow.material_override = sm
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	_shadow.visible = false
	add_child(_beam)
	add_child(_shadow)
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
