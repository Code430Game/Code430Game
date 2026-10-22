class_name VehicleDamage
extends Node3D
## A drivable car's damage (add-vehicle-and-building-damage): health from 100 down, lost to hard
## crashes (closing speed above `crash_min_mps`) and weapon hits (`vehicle_damage` per impact
## kind in combat_config.json). It shows in stages: scuffed (the body dulled), dented (the body
## pushed in around each hard hit, a light out on a front or rear hit), smoking (engine smoke,
## half the pull and top speed) and wrecked. A wreck follows the tone's `outcomes.vehicle`:
## "conk_out" stalls with puffs of smoke and is mended by a reset; "burn" smokes, catches fire
## after `burn_after_s`, explodes `explode_after_s` later (flinging and damaging what is near,
## so wrecks chain) and is left a blackened shell that burns out; "spark" does the same with
## sparks, a thin white smoke and blue-white flames. A mode without violence never burns. A child of the car, at the car's origin; tunables in vehicle_damage.json.

signal stage_changed(stage: int)
## The wreck blew up at `at` (world); `radius` metres.
signal exploded(at: Vector3, radius: float)

enum Stage { FINE, SCUFFED, DENTED, SMOKING, WRECKED }
enum Fire { NONE, SMOULDER, BURNING, SHELL }

const CONFIG_PATH := "res://actors/vehicles/vehicle_damage.json"
const MAX_HEALTH := 100.0
## Nodes in this group get `on_blast(at, radius, source)` when a wreck explodes (the testbed:
## the player, walkers, marks and sound).
const BLAST_GROUP := "blast_listeners"

static var _config: Dictionary = {}

var health: float = MAX_HEALTH
var stage: int = Stage.FINE
var fire: int = Fire.NONE
## Dents in the car's own frame: [{"at": Vector3, "depth": float}], oldest first.
var dents: Array = []
## Lights knocked out: "front" and/or "rear".
var lights_out: Dictionary = {}
## The wreck's outcome, fixed when it was wrecked.
var wreck_outcome: String = ""
## Body length and height, for where the engine smoke comes from.
var length_m: float = 4.6
var height_m: float = 1.5

var _fire_t: float = 0.0
var _smoke: CPUParticles3D
var _flames: CPUParticles3D
var _fire_light: OmniLight3D
var _sparks: CPUParticles3D


static func config() -> Dictionary:
	if _config.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config = data if data is Dictionary else {}
	return _config


static func tun(key: String) -> float:
	return float(config().get(key, 0.0))


## Health lost to a crash closing at `speed_mps`: none below `crash_min_mps`, then
## `crash_per_mps` for each m/s over it.
static func crash_damage(speed_mps: float) -> float:
	return maxf(speed_mps - tun("crash_min_mps"), 0.0) * tun("crash_per_mps")


## The stage for `h` health.
static func stage_for(h: float) -> int:
	if h <= 0.0:
		return Stage.WRECKED
	if h < tun("smoking_below"):
		return Stage.SMOKING
	if h < tun("dented_below"):
		return Stage.DENTED
	if h < tun("scuffed_below"):
		return Stage.SCUFFED
	return Stage.FINE


## What a wreck does in the active tone: "burn", "spark" or "conk_out". A mode without violence
## never burns.
static func outcome() -> String:
	var o := ContentMode.outcome("vehicle", "burn")
	if o != "burn" and o != "spark":
		return "conk_out"
	return o if ContentMode.flag("violence") else "conk_out"


## Burns and explodes (not a clean stall).
func burns() -> bool:
	return wreck_outcome == "burn" or wreck_outcome == "spark"


## Pull and top speed as a fraction of the car's: half once smoking, none wrecked.
func power_factor() -> float:
	if stage == Stage.WRECKED:
		return 0.0
	return tun("smoking_power") if stage == Stage.SMOKING else 1.0


func is_wrecked() -> bool:
	return stage == Stage.WRECKED


## A crash closing at `speed_mps`, at `local_at` on the body (the car's frame). Returns the
## health lost.
func crash(speed_mps: float, local_at: Vector3) -> float:
	var d := crash_damage(speed_mps)
	if d > 0.0:
		take(d, local_at)
	return d


## Loses `amount` health, hit at `local_at` (the car's frame). A hit of `dent_min` or more
## leaves a dent there; a front or rear hit once dented knocks out those lights.
func take(amount: float, local_at: Vector3) -> void:
	if amount <= 0.0 or stage == Stage.WRECKED:
		return
	health = maxf(health - amount, 0.0)
	if amount >= tun("dent_min"):
		var depth := minf(amount * tun("dent_depth_per_damage"), tun("dent_max_m"))
		dents.append({"at": local_at, "depth": depth})
		while dents.size() > int(tun("max_dents")):
			dents.pop_front()
	var s := stage_for(health)
	if s >= Stage.DENTED and absf(local_at.z) > length_m * 0.3:
		lights_out["front" if local_at.z < 0.0 else "rear"] = true
	_set_stage(s)


## Whole again: full health, no dents, no smoke or fire.
func mend() -> void:
	health = MAX_HEALTH
	dents.clear()
	lights_out.clear()
	fire = Fire.NONE
	wreck_outcome = ""
	_fire_t = 0.0
	_set_stage(Stage.FINE, true)


func _set_stage(s: int, force: bool = false) -> void:
	if s == stage and not force:
		return
	stage = s
	if s == Stage.WRECKED:
		wreck_outcome = outcome()
		fire = Fire.SMOULDER
		_fire_t = 0.0
	_update_effects()
	stage_changed.emit(s)


func _process(delta: float) -> void:
	if fire == Fire.NONE or not burns():
		return
	_fire_t += delta
	match fire:
		Fire.SMOULDER:
			if _fire_t >= tun("burn_after_s"):
				fire = Fire.BURNING
				_fire_t = 0.0
				_update_effects()
		Fire.BURNING:
			if _fire_t >= tun("explode_after_s"):
				fire = Fire.SHELL
				_fire_t = 0.0
				explode()
		Fire.SHELL:
			if _fire_t >= tun("shell_burn_s") and _flames != null and _flames.emitting:
				_flames.emitting = false
				if _fire_light != null:
					_fire_light.visible = false


## The wreck blows up: vehicles in `blast_radius_m` are flung away and lose health by distance
## (so a nearby wreck-to-be goes too), and the blast listeners hear of it.
func explode() -> void:
	fire = Fire.SHELL
	_update_effects()
	var at := global_position + Vector3.UP * 0.8
	var radius := tun("blast_radius_m")
	var me := get_parent()
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v == me or not (v is Node3D):
			continue
		var d := (v as Node3D).global_position.distance_to(at)
		if d > radius:
			continue
		var k := 1.0 - d / radius
		if v is RigidBody3D and not (v as RigidBody3D).freeze:
			var dir := ((v as Node3D).global_position - at + Vector3.UP * 1.5).normalized()
			(v as RigidBody3D).apply_central_impulse(dir * tun("blast_impulse") * k)
		var dmg: VehicleDamage = v.get("damage") if "damage" in v else null
		if dmg != null:
			dmg.take(tun("blast_car_damage") * k, (dmg.get_parent() as Node3D).to_local(at))
	for n in get_tree().get_nodes_in_group(BLAST_GROUP):
		n.on_blast(at, radius, me)
	exploded.emit(at, radius)


## Smoke, fire and their light for the current stage and fire.
func _update_effects() -> void:
	if not is_inside_tree():
		return
	var engine := Vector3(0.0, height_m * 0.7, -length_m * 0.32)
	var smoking := stage >= Stage.SMOKING
	if smoking and _smoke == null:
		_smoke = _emitter(engine, 24, 2.2)
	if _smoke != null:
		_smoke.emitting = smoking
		var c := Color(0.12, 0.12, 0.12, 0.7)  # black engine smoke
		if _look() == "conk_out":
			c = Color(0.75, 0.75, 0.75, 0.8)  # grey puffs
		elif _look() == "spark":
			c = Color(0.92, 0.94, 0.96, 0.5)  # thin white smoke under the sparks
		_smoke.color = c
		_smoke.amount = 10 if _look() == "conk_out" else 24
	var sparking := smoking and _look() == "spark"
	if sparking and _sparks == null:
		_sparks = _emitter(engine, 20, 0.5)
		_sparks.initial_velocity_min = 3.0
		_sparks.initial_velocity_max = 6.0
		_sparks.spread = 70.0
		_sparks.gravity = Vector3(0, -9.8, 0)
		_sparks.scale_amount_min = 0.08
		_sparks.scale_amount_max = 0.15
		_sparks.color = Color(0.7, 0.95, 1.0)
	if _sparks != null:
		_sparks.emitting = sparking
	var burning := fire == Fire.BURNING or (fire == Fire.SHELL and _fire_t < tun("shell_burn_s"))
	if burning and _flames == null:
		_flames = _emitter(Vector3(0.0, height_m * 0.6, 0.0), 64, 0.8)
		_flames.gravity = Vector3(0, 3.0, 0)
		_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_flames.emission_box_extents = Vector3(0.7, 0.3, length_m * 0.35)  # the whole body burns
		_flames.scale_amount_min = 1.0
		_flames.scale_amount_max = 2.0
		_fire_light = OmniLight3D.new()
		_fire_light.light_color = Color(1.0, 0.55, 0.2)
		_fire_light.light_energy = 2.5
		_fire_light.omni_range = 9.0
		_fire_light.position = Vector3(0, height_m, 0)
		add_child(_fire_light)
	if _flames != null:
		_flames.emitting = burning
		_flames.color = Color(0.6, 0.85, 1.0) if _look() == "spark" else Color(1.0, 0.5, 0.12)
		_fire_light.light_color = Color(0.6, 0.8, 1.0) if _look() == "spark" else Color(1.0, 0.55, 0.2)
		_fire_light.visible = burning


## How its smoke and fire look: the wreck's outcome once wrecked, the tone's before.
func _look() -> String:
	return wreck_outcome if wreck_outcome != "" else outcome()


## A small particle emitter at `pos`: `amount` unshaded quads rising for `life` seconds.
func _emitter(pos: Vector3, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.position = pos
	p.direction = Vector3.UP
	p.spread = 20.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	p.mesh = puff_mesh()
	# Each puff grows and fades out over its life.
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	add_child(p)
	return p


static var _puff: QuadMesh


## A soft round billboard, tinted by the particle colour: smoke, flames, sparks, the blast.
static func puff_mesh() -> QuadMesh:
	if _puff != null:
		return _puff
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_puff = QuadMesh.new()
	_puff.size = Vector2(0.7, 0.7)
	_puff.material = mat
	return _puff
