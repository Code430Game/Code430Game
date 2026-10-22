class_name FlyableHelicopter
extends VehicleBody3D
## The police helicopter as something the player can take and fly (add-flyable-helicopter).
##
## It is a VehicleBody3D with no wheels, so everything that works with the player's cars (the
## Player getting in and out, the chase camera, the minimap, streaming anchors, co-op state)
## works with it. Flight is arcade and set directly in _integrate_forces rather than through
## forces: the left stick asks for a horizontal velocity in the heading frame, the triggers for
## a climb or descent rate, the bumpers for a turn rate; each is approached at a fixed rate, so
## letting go brakes to a hover that holds its height. Tilt is only how it looks (pitch and
## roll from the velocity in its own frame). Descent slows near the ground, so a touch-down is
## gentle. Hard contacts follow the mode's `outcomes.aircraft`: "bounce" (bounce off and land
## gently, never destroyed) or "damage" (bounce, lose health, and at zero auto-rotate down to a
## heavy landing that leaves it disabled). With nobody flying it, it lands where it is and,
## once still, freezes in place (parked), so ground streaming away under it never drops it.
## It slides along what it touches rather than pressing into it, and the pilot holding reset
## (R3 / R) lifts it clear above whatever is under it (#140: it wedged in a tower's wall).
## Tunables come from helicopter_flight.json.

signal impacted(speed_mps: float)
## Became disabled (its health ran out): it can't fly again.
signal disabled_changed(disabled: bool)

const CONFIG_PATH := "res://actors/vehicles/helicopter_flight.json"

## Peer id of the player flying it, 0 when empty. Only the pilot's input reaches it.
var driver_peer_id: int = 0
var vehicle_id: String = "helicopter"
var body_color: Color = HelicopterModel.BODY_COLOR
## Radio station (the radio follows the player into any vehicle; Radio.pick_for_car fills it).
var radio_station: String = ""
## For the chase camera's framing (ChaseCamera reads length_m; chase_distance_m and
## chase_height_m override its distance and height for aircraft).
var length_m: float = 9.0
var chase_distance_m: float = 9.0
var chase_height_m: float = 3.5
## How quickly the chase camera catches up (higher than a car's, so it keeps up at speed).
var chase_smoothing: float = 14.0
## Kept for VehicleAudio's interface; the helicopter has its own rotor voice instead.
var engine_force_max: float = 1.0
## Tunables (helicopter_flight.json); missing keys fall back to the file's defaults below.
var config: Dictionary = {}
## The map's extent on x and z (soft boundary); empty: no boundary.
var bounds: Rect2 = Rect2()
## Overrides the pilot's input (tests and scripted flights): {"move": Vector2, "climb": float,
## "yaw": float}. Empty: read the pilot's controls.
var test_input: Dictionary = {}
## True on a guest's copy of the host's parked helicopter: getting in asks the host first.
var take_by_request: bool = false

var health: float = 100.0
var disabled: bool = false
var heading: float = 0.0
var engine: float = 0.0  # rotor spool, 0 stopped .. 1 flying
var height_above_ground: float = 0.0
## Parked and set down on the ground below (see _settle).
var settled: bool = false

var _velocity := Vector3.ZERO
var _yaw_rate: float = 0.0
var _tilt := Vector2.ZERO  # x pitch, y roll, radians
var _recover_s: float = 0.0  # after a hard hit: no control while it steadies
var _auto_land: bool = false  # clean's bounce: control comes back once it has landed
var _still_s: float = 0.0
var _touching: bool = false
var _ground_known: bool = false  # the ray below found ground (it may not have streamed in yet)
var _reset_hold_s: float = 0.0  # seconds the pilot has held reset; -1 once it fired
var _rotor: Node3D
var _tail_rotor: Node3D
var _rotor_voice: AudioStreamPlayer
var _rotor_phase: float = 0.0  # rotor beat phase in radians, wrapped at TAU so it never clicks
var _noise_state: Array = [0x7531]

const DEFAULTS := {
	"max_speed_mps": 42.0, "accel_mps2": 9.0, "brake_mps2": 12.0, "climb_mps": 10.0,
	"descend_mps": 8.0, "vertical_accel_mps2": 14.0, "yaw_rate_rad_s": 1.4,
	"yaw_accel_rad_s2": 4.0, "max_tilt_deg": 14.0, "tilt_speed": 4.0, "spool_s": 2.5,
	"lift_spool": 0.8, "ceiling_m": 180.0, "ceiling_push_mps": 4.0, "boundary_margin_m": 80.0,
	"boundary_push_mps": 0.25, "landed_m": 0.35, "exit_max_height_m": 2.0,
	"exit_max_speed_mps": 3.0, "auto_land_mps": 3.0, "park_after_s": 1.0, "ground_ray_m": 600.0,
	"crash_min_mps": 7.0, "crash_bounce": 0.4, "bounce_recover_s": 2.5, "health": 100.0,
	"crash_damage_per_mps": 6.0, "autorotate_mps": 9.0, "autorotate_glide": 0.6,
	"mass_kg": 2400.0, "chase_distance_m": 9.0, "chase_height_m": 3.5,
	"chase_pull_per_mps": 0.08, "rotor_gain": 0.6, "lookahead_s": 8.0, "lookahead_per_height": 1.0, "settle_m": 5.0, "chase_smoothing": 14.0,
	"lift_clear_m": 10.0, "lift_probe_m": 400.0,
}


func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	config = data if data is Dictionary else {}


func _ready() -> void:
	add_to_group("vehicles")
	mass = tun("mass_kg")
	health = tun("health")
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = false
	continuous_cd = true  # fast into a thin wall: stop at it, not inside the building
	heading = global_rotation.y
	var parts := HelicopterModel.build(self)
	_rotor = parts["rotor"]
	_tail_rotor = parts["tail_rotor"]
	var body := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = HelicopterModel.FUSELAGE_SIZE
	body.shape = box
	body.position = Vector3(0, HelicopterModel.FUSELAGE_Y, 0)
	add_child(body)
	var boom := CollisionShape3D.new()
	var boom_box := BoxShape3D.new()
	boom_box.size = HelicopterModel.BOOM_SIZE
	boom.shape = boom_box
	boom.position = HelicopterModel.BOOM_CENTRE
	add_child(boom)
	var skids := CollisionShape3D.new()  # the feet it stands on: a flat slab under the fuselage
	var skid_box := BoxShape3D.new()
	skid_box.size = Vector3(2.1, 0.3, 3.6)
	skids.shape = skid_box
	skids.position = Vector3(0, 0.15, 0)
	add_child(skids)
	var seat := Node3D.new()
	seat.name = "Seat"
	seat.position = Vector3(-1.3, 1.0, -0.8)
	add_child(seat)
	chase_distance_m = tun("chase_distance_m")
	chase_height_m = tun("chase_height_m")
	chase_smoothing = tun("chase_smoothing")
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		_rotor_voice = Synth.make_player("SFX", -6.0)
		add_child(_rotor_voice)


## A tunable from `config`, or its default.
func tun(key: String) -> float:
	return float(config.get(key, DEFAULTS[key]))


## Puts it at `t` (its heading follows) and parks it there.
func place_at(t: Transform3D) -> void:
	global_transform = t
	heading = t.basis.get_euler().y
	settled = false
	park()


## Parked where the ground had not streamed in yet (a pad far from the player): once a static
## surface turns up within `settle_m` above or below, it is set down on it.
func _settle() -> void:
	if not is_inside_tree():
		return
	var reach := tun("settle_m")
	var space := get_world_3d().direct_space_state
	# Below first (so a deck overhead never catches it), then just above (ground a little higher).
	var hit := {}
	for span: Array in [[0.5, -reach], [reach, 0.0]]:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * float(span[0]), global_position + Vector3.UP * float(span[1]))
		q.exclude = [get_rid()]
		hit = space.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] is StaticBody3D:
			break
		hit = {}
	if hit.is_empty():
		return
	global_position = hit["position"]
	height_above_ground = 0.0
	settled = true


## Parks it here: frozen in place, engine off, nobody aboard (the pad, or where it was left).
func park() -> void:
	_velocity = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	engine = 0.0
	_auto_land = false
	freeze = true


func is_parked() -> bool:
	return freeze


## Off the ground (not standing on its skids).
func airborne() -> bool:
	return height_above_ground > tun("landed_m")


## The pilot may get out: landed, or hovering within `exit_max_height_m`, and nearly still.
func can_exit() -> bool:
	return height_above_ground <= tun("exit_max_height_m") and linear_velocity.length() <= tun("exit_max_speed_mps")


func speed_kph() -> float:
	return linear_velocity.length() * 3.6


## Speed along its heading, m/s (VehicleAudio's interface).
func forward_speed() -> float:
	return -global_basis.z.dot(linear_velocity)


## Height above the ground below, metres (the HUD).
func altitude_m() -> float:
	return height_above_ground


## How far the pilot's reset hold has got, 0..1, for the HUD ring.
func reset_progress() -> float:
	return clampf(_reset_hold_s / Controls.hold_s(), 0.0, 1.0) if _reset_hold_s > 0.0 else 0.0


## Reset fires once it has been held for the hold time (a tap of R3 looks behind), then waits
## for a release so a long hold lifts it once.
func _step_reset_hold(held: bool, delta: float) -> void:
	if not held:
		_reset_hold_s = 0.0
		return
	if _reset_hold_s < 0.0:
		return
	_reset_hold_s += delta
	if _reset_hold_s >= Controls.hold_s():
		_reset_hold_s = -1.0
		lift_clear()


## Unsticks it: up to `lift_clear_m` above the highest static surface over or under it (a roof,
## a deck, the ground), never lower than it is, hovering there with no speed and the pilot in
## control. Returns where it went.
func lift_clear() -> Vector3:
	var p := global_position
	var top := p.y
	if is_inside_tree():
		var from := Vector3(p.x, p.y + tun("lift_probe_m"), p.z)
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(p.x, p.y - tun("ground_ray_m"), p.z))
		var exclude: Array[RID] = [get_rid()]
		for i in range(8):
			q.exclude = exclude
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if hit.is_empty():
				break
			if hit["collider"] is StaticBody3D:
				top = (hit["position"] as Vector3).y
				break
			exclude.append(hit["rid"])
	var at := Vector3(p.x, maxf(p.y, top + tun("lift_clear_m")), p.z)
	global_transform = Transform3D(Basis(Vector3.UP, heading), at)
	_velocity = Vector3.ZERO
	_yaw_rate = 0.0
	_tilt = Vector2.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_recover_s = 0.0
	_auto_land = false
	settled = false
	freeze = false
	return at


## What a hard hit does, from the mode data (`outcomes.aircraft`): "bounce" or "damage". A
## mode without violence never wrecks it.
static func outcome() -> String:
	var o := ContentMode.outcome("aircraft", "damage")
	return o if o == "bounce" or ContentMode.flag("violence") else "bounce"


func _physics_process(delta: float) -> void:
	if driver_peer_id != 0 and freeze and not disabled:
		freeze = false  # someone got in: off the pad
	if freeze and not settled:
		_settle()
	var flying := driver_peer_id != 0 and not disabled
	var spool_rate := delta / maxf(tun("spool_s"), 0.01)
	engine = move_toward(engine, 1.0 if flying or (airborne() and not disabled) else 0.0, spool_rate)
	_rotor.rotate_y(delta * 28.0 * engine)
	_tail_rotor.rotate_x(delta * 40.0 * engine)
	if driver_peer_id == 0 and not freeze and not airborne() and linear_velocity.length() < 0.3:
		_still_s += delta
		if _still_s >= tun("park_after_s"):
			park()
	else:
		_still_s = 0.0
	var pilot_here := driver_peer_id == Players.LOCAL_PEER_ID and not disabled and not get_tree().paused
	_step_reset_hold(pilot_here and Input.is_action_pressed("reset_vehicle"), delta)
	_fill_rotor()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	height_above_ground = _height_above_ground(state)
	_check_contacts(state)
	if freeze:
		return
	if disabled and not airborne():
		gravity_scale = 1.0  # wrecked and down: an ordinary heavy body
		return
	gravity_scale = 0.0
	var input := _pilot_input()
	var piloted := driver_peer_id != 0 and not disabled and _recover_s <= 0.0 and not _auto_land
	if _recover_s > 0.0:
		_recover_s -= dt
	if not piloted:
		input = {"move": Vector2.ZERO, "climb": 0.0, "yaw": 0.0}
	# Heading.
	_yaw_rate = move_toward(_yaw_rate, float(input["yaw"]) * tun("yaw_rate_rad_s"), tun("yaw_accel_rad_s2") * dt)
	heading = wrapf(heading + _yaw_rate * dt, -PI, PI)
	# Horizontal: stick asks for a velocity in the heading frame.
	var move: Vector2 = input["move"]
	if move.length() > 1.0:
		move = move.normalized()
	var desired := Basis(Vector3.UP, heading) * Vector3(move.x, 0.0, move.y) * tun("max_speed_mps")
	if disabled:
		desired = Vector3(_velocity.x, 0.0, _velocity.z) * tun("autorotate_glide")
	desired += boundary_push(state.transform.origin, bounds, tun("boundary_margin_m"), tun("boundary_push_mps"))
	var h := step_horizontal(Vector3(_velocity.x, 0.0, _velocity.z), desired, tun("accel_mps2"), tun("brake_mps2"), dt)
	# Vertical.
	var vy_goal := 0.0
	if disabled:
		vy_goal = -tun("autorotate_mps")
	elif driver_peer_id == 0 or _auto_land:
		vy_goal = -tun("auto_land_mps") if _ground_known else 0.0  # no ground below yet: hover, don't sink through
	else:
		vy_goal = desired_vertical(float(input["climb"]), height_above_ground, engine, config)
	if not disabled:
		vy_goal = soften_descent(vy_goal, height_above_ground)
	var vy := move_toward(_velocity.y, vy_goal, tun("vertical_accel_mps2") * dt)
	if not airborne() and vy < 0.0:
		vy = 0.0
		if _auto_land:
			_auto_land = false  # clean's bounce: down safely, the pilot has it again
	_velocity = slide_along(Vector3(h.x, vy, h.z), _contact_normals(state))
	state.linear_velocity = _velocity
	state.angular_velocity = Vector3.ZERO
	# Looks: pitch and roll from the velocity in its own frame, levelling when it slows.
	var local := Basis(Vector3.UP, heading).inverse() * _velocity
	var goal_tilt := tilt_for(local, tun("max_speed_mps"), deg_to_rad(tun("max_tilt_deg")))
	_tilt = _tilt.lerp(goal_tilt, clampf(tun("tilt_speed") * dt, 0.0, 1.0))
	var t := state.transform
	t.basis = Basis(Vector3.UP, heading) * Basis.from_euler(Vector3(_tilt.x, 0.0, _tilt.y))
	state.transform = t
	var pull := tun("chase_pull_per_mps") * h.length()
	chase_distance_m = tun("chase_distance_m") + pull
	chase_height_m = tun("chase_height_m") + pull * 0.4


## The pilot's input this frame (or `test_input`): move (stick, -y forward), climb (-1..1),
## yaw (-1..1, positive turns left).
func _pilot_input() -> Dictionary:
	if not test_input.is_empty():
		return {"move": test_input.get("move", Vector2.ZERO), "climb": float(test_input.get("climb", 0.0)), "yaw": float(test_input.get("yaw", 0.0))}
	if driver_peer_id != Players.LOCAL_PEER_ID or get_tree().paused:
		return {"move": Vector2.ZERO, "climb": 0.0, "yaw": 0.0}
	return {
		"move": Input.get_vector("move_left", "move_right", "move_forward", "move_back"),
		"climb": Input.get_action_strength("fly_up") - Input.get_action_strength("fly_down"),
		"yaw": Input.get_action_strength("fly_yaw_left") - Input.get_action_strength("fly_yaw_right"),
	}


## Velocity `v` moved toward `desired`: at `accel` while the stick asks for speed, at `brake`
## when it is let go (a quicker stop, so it holds where it is).
static func step_horizontal(v: Vector3, desired: Vector3, accel: float, brake: float, dt: float) -> Vector3:
	var rate := accel if desired.length() > 0.05 else brake
	return v.move_toward(desired, rate * dt)


## The climb (+) or descent (-) rate asked for by `climb` (-1..1) at `height` above the ground.
## Nothing pressed holds the height. It can't climb before the rotor is spooled up to
## `lift_spool`, and at or past `ceiling_m` it stops climbing and is pushed back down.
static func desired_vertical(climb: float, height: float, spool: float, cfg: Dictionary) -> float:
	var up := float(cfg.get("climb_mps", DEFAULTS["climb_mps"]))
	var down := float(cfg.get("descend_mps", DEFAULTS["descend_mps"]))
	var vy := climb * (up if climb > 0.0 else down)
	if spool < float(cfg.get("lift_spool", DEFAULTS["lift_spool"])):
		vy = minf(vy, 0.0)
	var ceiling := float(cfg.get("ceiling_m", DEFAULTS["ceiling_m"]))
	if height >= ceiling:
		vy = minf(vy, 0.0)
		if height > ceiling + 1.0:
			vy = -float(cfg.get("ceiling_push_mps", DEFAULTS["ceiling_push_mps"]))
	return vy


## Limits a descent near the ground so it touches down gently: no faster than about the
## height below plus one metre a second.
static func soften_descent(vy: float, height: float) -> float:
	if vy >= 0.0:
		return vy
	return maxf(vy, -(maxf(height, 0.0) * 1.2 + 1.0))


## A horizontal push back inside `rect` (x, z) once `pos` is within `margin` of its edge or
## beyond it: `push` m/s per metre past the margin line, pointing inward. An empty rect: none.
static func boundary_push(pos: Vector3, rect: Rect2, margin: float, push: float) -> Vector3:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector3.ZERO
	var inner := rect.grow(-margin)
	var out := Vector3.ZERO
	if pos.x < inner.position.x:
		out.x = (inner.position.x - pos.x) * push
	elif pos.x > inner.end.x:
		out.x = (inner.end.x - pos.x) * push
	if pos.z < inner.position.y:
		out.z = (inner.position.y - pos.z) * push
	elif pos.z > inner.end.y:
		out.z = (inner.end.y - pos.z) * push
	return out


## Pitch (x, nose down going forward) and roll (y, leaning into a sideways slide) for a
## velocity `local` in its own frame, up to `max_tilt` radians at `max_speed`.
static func tilt_for(local: Vector3, max_speed: float, max_tilt: float) -> Vector2:
	var k := max_tilt / maxf(max_speed, 0.01)
	return Vector2(clampf(local.z * k, -max_tilt, max_tilt), clampf(-local.x * k, -max_tilt, max_tilt))


## Height of its feet above the first static surface below (ground, deck, roof).
func _height_above_ground(state: PhysicsDirectBodyState3D) -> float:
	var from := state.transform.origin + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * tun("ground_ray_m"))
	var exclude: Array[RID] = [get_rid()]
	for i in range(4):
		q.exclude = exclude
		var hit := state.get_space_state().intersect_ray(q)
		if hit.is_empty():
			break
		if hit["collider"] is StaticBody3D:
			_ground_known = true
			return state.transform.origin.y - (hit["position"] as Vector3).y
		exclude.append(hit["rid"])
	_ground_known = false
	return tun("ground_ray_m")


## The normals of what it touches this step.
func _contact_normals(state: PhysicsDirectBodyState3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in range(state.get_contact_count()):
		out.append(state.get_contact_local_normal(i))
	return out


## `v` with no part pushing into any of `normals` (each pointing out of what it touches), so it
## slides along a wall or a roof instead of pressing into it. Before, the stick's velocity kept
## pushing it into a wall until it went through and wedged inside (#140).
static func slide_along(v: Vector3, normals: Array[Vector3]) -> Vector3:
	for n in normals:
		var into := v.dot(n)
		if into < 0.0:
			v -= n * into
	return v


## A hard contact (a wall, a deck's side, a roof edge, or the ground hit too fast) starts a hit.
func _check_contacts(state: PhysicsDirectBodyState3D) -> void:
	var touching := state.get_contact_count() > 0
	if touching and not _touching and not freeze:
		var worst := 0.0
		var normal := Vector3.UP
		for i in range(state.get_contact_count()):
			var n := state.get_contact_local_normal(i)
			var closing := -_velocity.dot(n)
			if closing > worst:
				worst = closing
				normal = n
		if worst >= tun("crash_min_mps"):
			hit(worst, normal)
	_touching = touching


## Hits something at `speed` (closing m/s) with contact normal `normal`: bounce back, and by the
## mode's outcome either land gently ("bounce") or lose health ("damage"; at zero it is wrecked
## and auto-rotates down).
func hit(speed: float, normal: Vector3) -> void:
	impacted.emit(speed)
	var into := _velocity.dot(normal)
	if into < 0.0:
		_velocity -= normal * into * (1.0 + tun("crash_bounce"))
	if outcome() == "bounce":
		_auto_land = true
		return
	health -= (speed - tun("crash_min_mps") * 0.5) * tun("crash_damage_per_mps")
	_recover_s = tun("bounce_recover_s")
	if health <= 0.0 and not disabled:
		health = 0.0
		disabled = true
		disabled_changed.emit(true)


## The rotor's thump for the pilot (non-positional, like the car engine): about 18 beats a
## second, as loud as the rotor is spooled up.
func _fill_rotor() -> void:
	if _rotor_voice == null:
		return
	if not _rotor_voice.playing:
		_rotor_voice.play()
	var pb := _rotor_voice.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var gain := engine * tun("rotor_gain") if driver_peer_id == Players.LOCAL_PEER_ID else 0.0
	var frames := pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(frames)
	var step := rotor_phase_step(18.0 * maxf(engine, 0.3), 1.0 / Synth.MIX_RATE)
	for i in range(frames):
		_rotor_phase = advance_phase(_rotor_phase, step)
		var beat := pow(maxf(sin(_rotor_phase), 0.0), 3.0)
		var s := Synth.noise(_noise_state) * beat * 0.5 * gain
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)


## Radians the rotor beat advances per sample at `beats_hz`.
static func rotor_phase_step(beats_hz: float, dt: float) -> float:
	return TAU * beats_hz * dt


## The next phase, wrapped at a whole turn so the waveform stays continuous forever; the old
## reset (fmod of elapsed seconds) cut mid-beat and clicked every ~1000 s.
static func advance_phase(phase: float, step: float) -> float:
	phase += step
	if phase >= TAU:
		phase -= TAU
	return phase
