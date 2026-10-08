class_name Shooter
extends Node
## The on-foot player's weapons (add-weapons-and-combat 2.2): LB / Tab cycles empty hands,
## melee and gun; LT / right mouse aims over the shoulder with a reticle; RT / left mouse fires
## or swings; B / R reloads. Guns raycast from the camera through the reticle; paintballs are
## pooled bodies with gravity; melee sweeps a short sphere in front of the player. Every hit
## goes through `hit()`: a mark on world surfaces, and on a person a knock-down for a lethal
## variant or paint and a run for a non-lethal one. Gunshots send walkers in earshot running.
##
## Empty hands (add-unarmed-combat): a tap of fire is a punch on release, alternating hands;
## fire held `kick_hold_s` (the leg draws up) and released is a kick with more reach. Fists
## go through `hit()` with the `fist` impact: where the tone allows violence the third punch
## on one person inside `combo_window_s`, or one kick, knocks them down; otherwise a hit is a
## shove that makes them stumble and run off.
##
## Choosing (add-weapon-selector): a tap of LB / Tab steps to the next slot; held past the
## wheel's `hold_s` it opens the `WeaponWheel`, and the release takes what the stick or mouse
## points at. Keys 1 to 9 pick by position. While the wheel is open the camera does not turn and
## fire, aim and reload do nothing; time never changes. The idle tile shows what is in hand and
## flashes on a change.

signal fired(weapon: Dictionary)
## A weapon hit a person; `downed` when it knocked them down (the police hear about it).
signal hit_person(agent: Pedestrian, weapon: Dictionary, downed: bool)

const BALL_POOL := 12
const BALL_LIFE_S := 2.0
const MUZZLE_UP_M := 1.35

var player: Player
var peds: PedestrianManager
## The police, whose officers the weapons reach (add-police-combat); null: none.
var police: PoliceManager
## The factions, whose members the weapons reach (add-hostile-gang); null: none.
var factions: FactionManager
var effects: CombatEffects
var weapons: WeaponSet
var hud: Label
var reticle: Control
## The weapon in the player's hand (2.6), made once the body's rig exists.
var held: HeldWeapon
## Aim as if the aim control were held (testbed screenshots).
var hold_aim: bool = false
## The weapon wheel and the idle tile (add-weapon-selector); either may be null.
var wheel: WeaponWheel
var tile: WeaponTile
var page: WeaponPage
var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _balls: Array[RigidBody3D] = []
var _ball_age: Dictionary = {}  # RigidBody3D -> seconds alive
var _paint_index: int = 0
var _fist_hold: float = -1.0  # seconds fire has been held with empty hands, or < 0
var _punch_side: int = 0
var _streaks: Dictionary = {}  # Pedestrian -> [punches in a row, _clock at the last]
var _clock: float = 0.0
var _next_held: float = -1.0  # seconds LB / Tab has been held, or < 0
var _wheel_this_press: bool = false  # the wheel already opened during this LB / Tab press
var _last_slot: int = 0


func _ready() -> void:
	weapons = WeaponSet.new()
	if effects != null:
		effects.palette = weapons.config.get("paint_colors", [])
		var caps: Dictionary = weapons.config.get("decal_cap", {})
		effects.cap = int(caps.get(Settings.current_preset_name, caps.get("deck", 48)))
	ContentMode.mode_changed.connect(_on_mode_changed)
	page = WeaponPage.new(weapons)
	if wheel != null and wheel.pages.is_empty():
		wheel.pages.append(page)
	_show_slot(false)


func _on_mode_changed(_id: String) -> void:
	weapons.refill()
	if weapons.slot > 0 and weapons.current().is_empty():
		weapons.slot = 0
	if effects != null:
		effects.clear_marks()
	_show_slot(false)
	_update_hud()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_clock += delta
	_step_balls(delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			weapons.reload()
	var active := player != null and not player.is_driving() and not get_tree().paused and player.stuck_s <= 0.0
	_ensure_held()
	if held != null:
		held.set_weapon(weapons.current() if player != null and not player.is_driving() else {})
	if tile != null:
		tile.visible = player != null and not player.is_driving()
	if not active:
		if wheel != null:
			wheel.close(false)
		_next_held = -1.0
		if player != null:
			player.aiming = false
			player.look_locked = false
		if held != null:
			held.aiming = false
		_drop_fists()
		_show_reticle(false)
		return
	step_next(delta, Input.is_action_pressed("weapon_next"))
	for i in range(9):
		if Input.is_action_just_pressed("weapon_slot_%d" % (i + 1)):
			pick_position(i)
	_sync_slot()
	var choosing := wheel != null and wheel.is_open()
	player.look_locked = choosing
	if choosing or (wheel != null and wheel.just_closed()):
		if choosing:
			wheel.steer(Input.get_vector("look_left", "look_right", "look_up", "look_down"))
		player.aiming = false
		if held != null:
			held.aiming = false
		_drop_fists()
		_show_reticle(false)
		_update_hud()
		return
	var w := weapons.current()
	player.aiming = not w.is_empty() and (Input.is_action_pressed("aim") or hold_aim)
	_show_reticle(player.aiming and w.get("mechanic", "") != "melee")
	if held != null:
		held.aiming = player.aiming and w.get("mechanic", "") != "melee"
	if w.is_empty():
		step_fists(delta, Input.is_action_pressed("fire"))
	else:
		if Input.is_action_just_pressed("reload"):
			start_reload()
		if Input.is_action_pressed("fire"):
			pull_trigger()
	_update_hud()


## LB / Tab, one physics step: released before the wheel's `hold_s` it steps to the next slot;
## held past it the wheel opens, and the release takes what the wheel points at.
func step_next(delta: float, pressed: bool) -> void:
	var hold := float(WeaponWheel.tunables().get("hold_s", 0.2))
	if pressed:
		if _next_held < 0.0:
			_next_held = 0.0
			_wheel_this_press = false
		else:
			_next_held += delta
		# One wheel per press: a wheel cancelled with B / Esc stays shut until LB is let go.
		if wheel != null and not wheel.is_open() and _next_held >= hold and not _wheel_this_press:
			wheel.open_wheel()
			_wheel_this_press = true
		return
	if _next_held < 0.0:
		return
	var held_for := _next_held
	_next_held = -1.0
	var before := weapons.slot
	if wheel != null and wheel.is_open():
		wheel.close(true)
	elif held_for < hold or wheel == null:
		weapons.cycle()
	if weapons.slot != before:
		_switched()


## Picks the `index`th slot the tone fills (keys 1 to 9). Returns true when it did.
func pick_position(index: int) -> bool:
	var slots := weapons.available()
	var before := weapons.slot
	if index < 0 or index >= slots.size() or not weapons.pick(slots[index]):
		return false
	if weapons.slot != before:
		_switched()
	return true


## The player switched weapons: no reload carries over, the fists let go, the tile flashes.
func _switched() -> void:
	_reload_left = 0.0
	_drop_fists()
	_show_slot(true)


## Keeps the idle tile on what is in hand, however the slot changed (the testbed sets it).
func _sync_slot() -> void:
	if weapons.slot != _last_slot:
		_show_slot(true)


func _show_slot(flash: bool) -> void:
	_last_slot = weapons.slot
	if tile != null:
		tile.show_icon(WeaponIcons.texture(weapons.icon_names(weapons.slot)))
		if flash:
			tile.flash()


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


## Starts a reload of the weapon in hand, unless it has no magazine, the magazine is full or a
## reload is already running. Returns true when it started one.
func start_reload() -> bool:
	var w := weapons.current()
	var mag := int(w.get("magazine", 0))
	if mag <= 0 or _reload_left > 0.0 or weapons.rounds() >= mag:
		return false
	_reload_left = float(w.get("reload_s", 1.0))
	return true


## Puts the weapons back to rest (busted, wasted): wheel shut, no reload, cooldown, held fire,
## LB hold or punch streaks carried over. The slot and the rounds stay.
func reset() -> void:
	if wheel != null:
		wheel.close(false)
	_next_held = -1.0
	_wheel_this_press = false
	_reload_left = 0.0
	_cooldown = 0.0
	_streaks.clear()
	_drop_fists()
	if player != null:
		player.aiming = false
		player.look_locked = false
	if held != null:
		held.aiming = false
	_show_reticle(false)
	_update_hud()


## The empty-hands tunables from combat_config.json.
func fists() -> Dictionary:
	return weapons.config.get("fists", {})


## Fists as a weapon for the hit path: `move` is "punch" or "kick".
func fist_weapon(move: String) -> Dictionary:
	var f := fists()
	return {
		"id": "fists", "name": "Fists", "mechanic": "melee", "impact": "fist", "lethal": false, "move": move,
		"range_m": float(f.get(move + "_range_m", 1.3)), "rate_s": float(f.get(move + "_rate_s", 0.35)),
	}


## Empty hands, one physics step: fire `pressed` or not. Released before `kick_hold_s` it is a
## punch, after it a kick; past the threshold the leg draws up.
func step_fists(delta: float, pressed: bool) -> void:
	var kick_at := float(fists().get("kick_hold_s", 0.4))
	if pressed:
		_fist_hold = 0.0 if _fist_hold < 0.0 else _fist_hold + delta
		if held != null:
			held.chamber = _fist_hold >= kick_at
		return
	if _fist_hold < 0.0:
		return
	var long := _fist_hold >= kick_at
	_fist_hold = -1.0
	if long:
		kick()
	else:
		punch()


## A punch with the next hand, if ready. Returns true when it was thrown.
func punch() -> bool:
	if _cooldown > 0.0:
		return false
	var w := fist_weapon("punch")
	_cooldown = float(w["rate_s"])
	if held != null:
		held.punch(_punch_side)
	_punch_side = 1 - _punch_side
	_swing(w)
	fired.emit(w)
	return true


## A kick, if ready. Returns true when it was thrown.
func kick() -> bool:
	if held != null:
		held.chamber = false
	if _cooldown > 0.0:
		return false
	var w := fist_weapon("kick")
	_cooldown = float(w["rate_s"])
	if held != null:
		held.kick()
	_swing(w)
	fired.emit(w)
	return true


func _drop_fists() -> void:
	_fist_hold = -1.0
	if held != null:
		held.chamber = false


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
		if body is OfficerBody and police != null and police.in_fight((body as OfficerBody).officer):
			hit(w, body, centre, -fwd, player.global_position)
			return
		if body is FactionBody and factions != null and (factions.mirror or factions.in_fight((body as FactionBody).member)):
			hit(w, body, centre, -fwd, player.global_position)
			return
		var who: Pedestrian = peds.agent_of(body as Node) if peds != null and body is Node else null
		if who != null and who.state == Pedestrian.State.WALKING:
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
	# The world, walkers' bodies and officers: a paintball has to land on people, not just walls.
	b.collision_mask = 1 | PedestrianBody.LAYER | OfficerBody.LAYER
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
	if collider is OfficerBody:
		_hit_officer((collider as OfficerBody).officer, w, pos, from)
		return
	if collider is FactionBody:
		_hit_member((collider as FactionBody).member, w, pos, from)
		return
	var a: Pedestrian = peds.agent_of(collider as Node) if peds != null and collider is Node else null
	if a != null and a.state != Pedestrian.State.WALKING:
		return  # already down or falling: nothing more happens, and no new crime is reported
	if a != null and kind == "fist":
		_fist_hit(a, w, pos, from)
		return
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


## A hit on a police officer (add-police-combat): the PoliceManager decides what it does; a
## knock-down by a lethal weapon leaves blood where gore is allowed, and paint marks the ground
## by a tagged-out officer.
func _hit_officer(o: Node3D, w: Dictionary, pos: Vector3, from: Vector3) -> void:
	if police == null or o == null:
		return
	var kind := str(w.get("impact", ""))
	var result := police.hit_officer(o, w, pos, from)
	if result == "" or effects == null:
		return
	if kind == "fist":
		effects.sound(str(weapons.impact("fist").get("sound", "")))
	if result == "down" and bool(w.get("lethal", false)) and ContentMode.allows("gore"):
		effects.mark("blood", o.global_position + Vector3.UP * 0.02, Vector3.UP)
	elif kind == "paint":
		_paint_index = (_paint_index + 1) % 4
		effects.mark(str(weapons.impact(kind).get("decal", "")), o.global_position + Vector3.UP * 0.02, Vector3.UP, _paint_index)


## A hit on a gang member (add-hostile-gang): the FactionManager decides what it does (and a
## guest's hit goes to the host); blood where a lethal weapon downs them and gore is allowed,
## paint by a tagged-out member.
func _hit_member(m: GangMember, w: Dictionary, pos: Vector3, from: Vector3) -> void:
	if factions == null or m == null:
		return
	var kind := str(w.get("impact", ""))
	var result := factions.hit_member(m, w, pos, from)
	if result == "" or result == "sent" or effects == null:
		return
	if kind == "fist":
		effects.sound(str(weapons.impact("fist").get("sound", "")))
	if result == "down" and bool(w.get("lethal", false)) and ContentMode.allows("gore"):
		effects.mark("blood", m.global_position + Vector3.UP * 0.02, Vector3.UP)
	elif kind == "paint":
		_paint_index = (_paint_index + 1) % 4
		effects.mark(str(weapons.impact(kind).get("decal", "")), m.global_position + Vector3.UP * 0.02, Vector3.UP, _paint_index)


## A punch or kick landing on a walker: a knock-down for a kick or the punch that completes a
## streak where the tone allows violence, otherwise a shove (stumble, then run off).
func _fist_hit(a: Pedestrian, w: Dictionary, pos: Vector3, from: Vector3) -> void:
	var f := fists()
	var kicked := str(w.get("move", "")) == "kick"
	var downed := false
	if ContentMode.flag("violence"):
		if kicked:
			downed = true
		else:
			var last: Array = _streaks.get(a, [0, -INF])
			var n := int(last[0]) + 1 if _clock - float(last[1]) <= float(f.get("combo_window_s", 2.5)) else 1
			_streaks[a] = [n, _clock]
			downed = n >= int(f.get("punches_to_down", 3))
	_forget_old_streaks(float(f.get("combo_window_s", 2.5)))
	if downed:
		_streaks.erase(a)
		var push := pos - from
		push.y = 0.0
		var strength := float(f.get("kick_push", 300.0)) if kicked else float(weapons.impact("fist").get("lethal_push", 180.0))
		peds.knock_down(a, push.normalized() * strength + Vector3.UP * 40.0, pos)
	else:
		peds.shove(a, from, float(f.get("stumble_s", 0.6)), float(weapons.config.get("flee_s", 6.0)))
	if effects != null:
		effects.sound(str(weapons.impact("fist").get("sound", "")))
	hit_person.emit(a, w, downed)


func _forget_old_streaks(window: float) -> void:
	for p: Pedestrian in _streaks.keys():
		if _clock - float(_streaks[p][1]) > window:
			_streaks.erase(p)


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
