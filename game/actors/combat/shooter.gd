class_name Shooter
extends Node
## The on-foot player's weapons (add-weapons-and-combat 2.2): LB / Tab cycles empty hands,
## melee and gun; LT / right mouse aims over the shoulder with a reticle; RT / left mouse fires
## or swings; B / R reloads. Guns raycast from the camera through the reticle; paintballs are
## pooled bodies with gravity; melee sweeps a short sphere in front of the player. Every hit
## goes through `hit()`: a mark on world surfaces, and on a person a knock-down for a lethal
## variant or paint and a run for a non-lethal one. Gunshots send walkers in earshot running.

signal fired(weapon: Dictionary)
## A weapon hit a person; `downed` when it knocked them down (the police hear about it).
signal hit_person(agent: Pedestrian, weapon: Dictionary, downed: bool)

const BALL_POOL := 12
const BALL_LIFE_S := 2.0
const MUZZLE_UP_M := 1.35

var player: Player
var peds: PedestrianManager
var effects: CombatEffects
var weapons: WeaponSet
var hud: Label
var reticle: Control
## The weapon in the player's hand (2.6), made once the body's rig exists.
var held: HeldWeapon
## Aim as if the aim control were held (testbed screenshots).
var hold_aim: bool = false
var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _balls: Array[RigidBody3D] = []
var _ball_age: Dictionary = {}  # RigidBody3D -> seconds alive
var _paint_index: int = 0


func _ready() -> void:
	weapons = WeaponSet.new()
	if effects != null:
		effects.palette = weapons.config.get("paint_colors", [])
		var caps: Dictionary = weapons.config.get("decal_cap", {})
		effects.cap = int(caps.get(Settings.current_preset_name, caps.get("deck", 48)))
	ContentMode.mode_changed.connect(_on_mode_changed)


func _on_mode_changed(_id: String) -> void:
	weapons.refill()
	if weapons.slot > 0 and weapons.current().is_empty():
		weapons.slot = 0
	if effects != null:
		effects.clear_marks()
	_update_hud()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_step_balls(delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			weapons.reload()
	var active := player != null and not player.is_driving() and not get_tree().paused and player.stuck_s <= 0.0
	_ensure_held()
	if held != null:
		held.set_weapon(weapons.current() if player != null and not player.is_driving() else {})
	if not active:
		if player != null:
			player.aiming = false
		if held != null:
			held.aiming = false
		_show_reticle(false)
		return
	if Input.is_action_just_pressed("weapon_next"):
		weapons.cycle()
		_reload_left = 0.0
	var w := weapons.current()
	player.aiming = not w.is_empty() and (Input.is_action_pressed("aim") or hold_aim)
	_show_reticle(player.aiming and w.get("mechanic", "") != "melee")
	if held != null:
		held.aiming = player.aiming and w.get("mechanic", "") != "melee"
	if not w.is_empty():
		if Input.is_action_just_pressed("reload") and int(w.get("magazine", 0)) > 0:
			_reload_left = float(w.get("reload_s", 1.0))
		if Input.is_action_pressed("fire"):
			pull_trigger()
	_update_hud()


## Fires or swings once if the weapon is ready. Returns true when it did.
func pull_trigger() -> bool:
	var w := weapons.current()
	if w.is_empty() or _cooldown > 0.0 or _reload_left > 0.0:
		return false
	var mag := int(w.get("magazine", 0))
	if mag > 0 and weapons.rounds() <= 0:
		_reload_left = float(w.get("reload_s", 1.0))
		return false
	_cooldown = float(w.get("rate_s", 0.3))
	if mag > 0:
		weapons.use_round()
	var imp := weapons.impact(str(w.get("impact", "")))
	match str(w.get("mechanic", "")):
		"melee":
			if held != null:
				held.swing()
			_swing(w)
		"projectile":
			if held != null:
				held.recoil()
			_launch(w)
		_:
			if held != null:
				held.recoil()
			_shoot(w)
	if effects != null:
		effects.sound(str(imp.get("sound", "")))
	fired.emit(w)
	return true


func _aim_ray(range_m: float, spread_deg: float) -> Array:
	var cam := player.camera()
	var from := cam.global_position
	var dir := -cam.global_basis.z
	if spread_deg > 0.0:
		var s := deg_to_rad(spread_deg)
		dir = dir.rotated(cam.global_basis.x, randf_range(-s, s)).rotated(cam.global_basis.y, randf_range(-s, s))
	return [from, from + dir.normalized() * range_m]


func _muzzle() -> Vector3:
	if held != null and held.muzzle() != Vector3.INF:
		return held.muzzle()  # the barrel's end in the hand
	var cam := player.camera()
	return player.global_position + Vector3.UP * MUZZLE_UP_M + cam.global_basis.x * 0.35 - cam.global_basis.z * 0.5


func _shoot(w: Dictionary) -> void:
	var ray := _aim_ray(float(w.get("range_m", 60.0)), float(w.get("spread_deg", 0.0)))
	var q := PhysicsRayQueryParameters3D.create(ray[0], ray[1])
	q.exclude = [player.get_rid()]
	var res := player.get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = res["position"] if not res.is_empty() else ray[1]
	var muzzle := _muzzle()
	if effects != null:
		var energy := str(w.get("impact", "")) == "energy"
		effects.flash(muzzle, Color(0.4, 0.9, 1.0) if energy else Color(1.0, 0.85, 0.5))
		if bool(w.get("tracer", false)):
			effects.tracer(muzzle, end)
	if not res.is_empty():
		hit(w, res["collider"], res["position"], res["normal"], muzzle)
	if peds != null and str(w.get("impact", "")) in ["bullet", "energy"]:
		peds.flee(player.global_position, float(weapons.config.get("earshot_m", 30.0)), float(weapons.config.get("flee_s", 6.0)))


func _swing(w: Dictionary) -> void:
	var fwd := -player.camera().global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var centre := player.global_position + Vector3.UP * 1.0 + fwd * (float(w.get("range_m", 1.8)) * 0.6)
	var shape := SphereShape3D.new()
	shape.radius = float(w.get("range_m", 1.8)) * 0.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), centre)
	q.exclude = [player.get_rid()]
	for r in player.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var body: Object = r["collider"]
		if peds != null and peds.agent_of(body as Node) != null:
			hit(w, body, centre, -fwd, player.global_position)
			return
	# Nobody there: a paint brush still daubs the wall it touches.
	var wall := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, centre + fwd * 0.6)
	wall.exclude = [player.get_rid()]
	var res := player.get_world_3d().direct_space_state.intersect_ray(wall)
	if not res.is_empty():
		hit(w, res["collider"], res["position"], res["normal"], player.global_position)


func _launch(w: Dictionary) -> void:
	var ball: RigidBody3D = null
	for b in _balls:
		if not _ball_age.has(b):
			ball = b
			break
	if ball == null:
		if _balls.size() >= BALL_POOL:
			ball = _balls[0]
		else:
			ball = _make_ball()
	var ray := _aim_ray(float(w.get("range_m", 45.0)), float(w.get("spread_deg", 0.0)))
	var muzzle := _muzzle()
	ball.set_meta("weapon", w)
	ball.freeze = false
	ball.visible = true
	ball.global_position = muzzle
	ball.linear_velocity = (ray[1] - muzzle).normalized() * float(w.get("speed_mps", 40.0))
	_ball_age[ball] = 0.0
	if effects != null:
		effects.flash(muzzle, Color(0.9, 0.95, 1.0))


func _make_ball() -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = 0.05
	b.contact_monitor = true
	b.max_contacts_reported = 1
	b.continuous_cd = true
	b.add_collision_exception_with(player)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.06
	shape.shape = sphere
	b.add_child(shape)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	mesh.mesh = sm
	b.add_child(mesh)
	b.body_entered.connect(_on_ball_hit.bind(b))
	(player.get_parent() if player.get_parent() != null else self).add_child(b)
	b.freeze = true
	b.visible = false
	_balls.append(b)
	return b


func _on_ball_hit(body: Node, ball: RigidBody3D) -> void:
	if not _ball_age.has(ball):
		return
	var w: Dictionary = ball.get_meta("weapon", {})
	var v := ball.linear_velocity
	hit(w, body, ball.global_position, -v.normalized() if v.length() > 0.1 else Vector3.UP, player.global_position)
	_retire(ball)


func _step_balls(delta: float) -> void:
	for b: RigidBody3D in _ball_age.keys():
		_ball_age[b] = float(_ball_age[b]) + delta
		if float(_ball_age[b]) > BALL_LIFE_S:
			_retire(b)


func _retire(ball: RigidBody3D) -> void:
	_ball_age.erase(ball)
	ball.set_deferred("freeze", true)
	ball.visible = false
	ball.set_deferred("global_position", Vector3(0, -1000, 0))


## One hit, whatever made it: a mark on world surfaces; on a walker, a knock-down for a
## lethal variant (blood only where gore is allowed) or paint and a run for a non-lethal one.
func hit(w: Dictionary, collider: Object, pos: Vector3, normal: Vector3, from: Vector3) -> void:
	var kind := str(w.get("impact", ""))
	var imp := weapons.impact(kind)
	var a: Pedestrian = peds.agent_of(collider as Node) if peds != null and collider is Node else null
	if a != null:
		if bool(w.get("lethal", false)) and ContentMode.flag("lethal_weapons"):
			var push := (pos - from)
			push.y = 0.0
			push = push.normalized() * float(imp.get("lethal_push", 400.0)) + Vector3.UP * 60.0
			peds.knock_down(a, push, pos)
			hit_person.emit(a, w, true)
			if effects != null and ContentMode.allows("gore"):
				effects.mark("blood", a.position() + Vector3.UP * 0.02, Vector3.UP)
		else:
			_paint_index = (_paint_index + 1) % 4
			peds.paint(a, _paint_index, from, float(weapons.config.get("flee_s", 6.0)))
			hit_person.emit(a, w, false)
		return
	if effects != null and collider is StaticBody3D:
		_paint_index = (_paint_index + 1) % 4
		effects.mark(str(imp.get("decal", "")), pos, normal, _paint_index)


func _ensure_held() -> void:
	if held != null or player == null or player.rig() == null:
		return
	held = HeldWeapon.new()
	held.name = "HeldWeapon"
	held.rig = player.rig()
	player.add_child(held)


func _show_reticle(on: bool) -> void:
	if reticle != null:
		reticle.visible = on


func _update_hud() -> void:
	if hud == null:
		return
	var w := weapons.current()
	if w.is_empty():
		hud.text = ""
		return
	var text := str(w.get("name", ""))
	if int(w.get("magazine", 0)) > 0:
		text += "   %d / %d" % [weapons.rounds(), int(w.get("magazine", 0))]
		if _reload_left > 0.0:
			text += "   reloading"
	hud.text = text
