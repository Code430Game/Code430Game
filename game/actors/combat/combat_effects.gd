class_name CombatEffects
extends Node3D
## What a hit leaves and how a shot looks and sounds (add-weapons-and-combat 2.3): a pool of
## marks on world surfaces (paint splats, bullet holes, scorch marks) recycled oldest first
## past the preset's cap, a muzzle flash, a glowing tracer for energy bolts, and synthesised
## shot, zap, swish, pop and thud voices.

const MARK_SIZE := {"splat": 0.55, "hole": 0.12, "scorch": 0.4, "blood": 0.9, "blast": 5.0}
const MARK_COLOR := {"hole": Color(0.08, 0.08, 0.08), "scorch": Color(0.1, 0.07, 0.05), "blood": Color(0.32, 0.02, 0.02), "blast": Color(0.06, 0.05, 0.04)}
const VOICE_S := {"boom": 1.6}  # how long a voice lasts; the rest are short (0.3 s)
const TRACER_COLOR := Color(0.4, 0.9, 1.0)

var cap: int = 48
var palette: Array = []
var _marks: Array[MeshInstance3D] = []
var _next: int = 0
var _materials: Dictionary = {}
var _voice: AudioStreamPlayer
var _events: Array = []  # [kind, seconds left]
var _phase: float = 0.0
var _noise: Array = [0x2545F491]


func _ready() -> void:
	_voice = Synth.make_player("SFX", -6.0)
	add_child(_voice)
	_voice.play()


## Leaves a mark of `kind` at `pos` facing `normal`. Paint takes palette colour `tint`.
func mark(kind: String, pos: Vector3, normal: Vector3, tint: int = 0) -> void:
	if kind == "" or cap <= 0:
		return
	var m: MeshInstance3D
	if _marks.size() < cap:
		m = MeshInstance3D.new()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_marks.append(m)
	else:
		m = _marks[_next]
		_next = (_next + 1) % _marks.size()
	m.mesh = _shape(kind)
	m.scale = Vector3.ONE * float(MARK_SIZE.get(kind, 0.3)) * randf_range(0.8, 1.25)
	var color: Color = MARK_COLOR.get(kind, Color.WHITE)
	if kind == "splat" and not palette.is_empty():
		var c: Array = palette[tint % palette.size()]
		color = Color(float(c[0]), float(c[1]), float(c[2]))
	m.material_override = _material(color)
	var n := normal.normalized()
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
	var scale := m.scale
	m.global_transform = Transform3D(Basis.looking_at(-n, up).rotated(n, randf() * TAU), pos + n * 0.015)
	m.scale = scale
	m.visible = true


## A flat fan in the XY plane facing +Z, unit size: a lumpy blob for paint and blood, a disc
## for holes and scorches. Built once per kind.
func _shape(kind: String) -> ArrayMesh:
	var key := "shape:" + kind
	if _materials.has(key):
		return _materials[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 14
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var lumpy := kind == "splat" or kind == "blood"
	var rim: Array[Vector3] = []
	for k in range(sides):
		var a := TAU * k / sides
		var r := 0.5 * (rng.randf_range(0.6, 1.15) if lumpy else 1.0)
		rim.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	for k in range(sides):
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(rim[(k + 1) % sides])
		st.add_vertex(rim[k])
	var mesh := st.commit()
	_materials[key] = mesh
	return mesh


func clear_marks() -> void:
	for m in _marks:
		m.visible = false


func marks_shown() -> int:
	return _marks.filter(func(m: MeshInstance3D) -> bool: return m.visible).size()


func _material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.roughness = 0.9
		_materials[key] = mat
	return _materials[key]


## A short flash at the muzzle.
func flash(at: Vector3, color: Color = Color(1.0, 0.85, 0.5)) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 3.0
	l.omni_range = 6.0
	add_child(l)
	l.global_position = at
	get_tree().create_timer(0.06, false).timeout.connect(l.queue_free)


## A wreck exploding at `at` (add-vehicle-and-building-damage): a bright flash that fades, a
## burst of fire, a scorch on the ground below, and a boom. `color` tints the flash and fire.
func blast(at: Vector3, color: Color = Color(1.0, 0.6, 0.25)) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 14.0
	l.omni_range = 22.0
	add_child(l)
	l.global_position = at + Vector3.UP * 1.5
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 40
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	p.mesh = VehicleDamage.puff_mesh()
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(0.2, 0.2, 0.2, 0))
	p.color_ramp = fade
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.5, false).timeout.connect(p.queue_free)
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 6.0)
		q.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] is StaticBody3D:
			mark("blast", hit["position"], hit["normal"])
	sound("boom")


## A glowing bolt from `a` to `b` that fades out (energy weapons).
func tracer(a: Vector3, b: Vector3) -> void:
	var len := a.distance_to(b)
	if len < 0.1:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, len)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = TRACER_COLOR
	mat.emission_enabled = true
	mat.emission = TRACER_COLOR
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var mid := (a + b) * 0.5
	mi.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), mid)
	get_tree().create_timer(0.09, false).timeout.connect(mi.queue_free)


## Queues a voice: "shot", "zap", "swish", "pop", "thud" (a punch or kick landing) or "boom"
## (a wreck exploding).
func sound(kind: String) -> void:
	if kind != "":
		_events.append([kind, 0.0])


func _process(_delta: float) -> void:
	var pb := _voice.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null or _events.is_empty():
		return
	var frames := pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(frames)
	var dt := 1.0 / Synth.MIX_RATE
	for i in range(frames):
		var s := 0.0
		for e: Array in _events:
			var t: float = e[1]
			e[1] = t + dt
			s += _sample(str(e[0]), t)
		buf[i] = Vector2(s, s) * 0.6
	pb.push_buffer(buf)
	_events = _events.filter(func(e: Array) -> bool: return float(e[1]) < float(VOICE_S.get(e[0], 0.3)))


func _sample(kind: String, t: float) -> float:
	match kind:
		"shot":
			return Synth.noise(_noise) * exp(-t * 30.0) * 0.9 + sin(t * TAU * 90.0) * exp(-t * 22.0) * 0.5
		"zap":
			var f := lerpf(1400.0, 180.0, clampf(t / 0.2, 0.0, 1.0))
			_phase += TAU * f / Synth.MIX_RATE
			return (1.0 if fmod(_phase, TAU) < PI else -1.0) * exp(-t * 14.0) * 0.35
		"swish":
			return Synth.noise(_noise) * sin(clampf(t / 0.16, 0.0, 1.0) * PI) * 0.35
		"pop":
			return sin(t * TAU * 140.0) * exp(-t * 40.0) * 0.6 + Synth.noise(_noise) * exp(-t * 90.0) * 0.4
		"boom":
			return clampf((Synth.noise(_noise) * exp(-t * 3.0) + sin(t * TAU * 42.0) * exp(-t * 4.0)) * 0.9, -1.0, 1.0)
		"thud":
			return sin(t * TAU * 70.0) * exp(-t * 28.0) * 0.7 + Synth.noise(_noise) * exp(-t * 60.0) * 0.25
	return 0.0
