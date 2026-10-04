class_name PedHitLab
extends Node3D
## A repeatable pedestrian hit: the player's car on a straight flat road at a set speed and one
## pedestrian walking a crossing timed to meet it. Measures the car's speed just before contact
## and its lowest speed over the next 1.5 s, and how fast the person is thrown, then prints one
## "ped-hit:" line. `--no-walker` gives the coasting baseline over the same stretch. Built for recordings (`--write-movie`) and tests, not for play.
##
## Run: Godot --path game res://scenes/ped_hit_lab.tscn -- --speed-kph=50 --exit-after=8

signal finished(result: Dictionary)

const CAR_START_Z := 70.0
const CONTACT_Z := 2.6  # car centre when its nose (2.1 m ahead) reaches the walker
const MEASURE_S := 1.5
const MEASURE_FROM_Z := CONTACT_Z + 3.0  # car centre where the measurement starts, just before contact

var speed_kph: float = 50.0
var exit_after_s: float = -1.0
var with_walker: bool = true  # false (--no-walker): the coasting baseline
var brake_after_hit: bool = false  # --brake: brake hard 0.3 s after contact, as a driver would (recordings)
var car: VehicleBody3D
var peds: PedestrianManager
var walker: Pedestrian
var result: Dictionary = {}
var _elapsed: float = 0.0
var _hit_at: float = -1.0
var _before_kph: float = -1.0
var _lowest_kph: float = INF
var _peak_ped_mps: float = 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed-kph="):
			speed_kph = float(arg.get_slice("=", 1))
		elif arg.begins_with("--exit-after="):
			exit_after_s = float(arg.get_slice("=", 1))
		elif arg == "--no-walker":
			with_walker = false
		elif arg == "--brake":
			brake_after_hit = true
	_build_world()
	_build_car()
	if with_walker:
		_build_pedestrian()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.74, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 300)
	shape.shape = box
	shape.position = Vector3(0, -0.5, -40)
	ground.add_child(shape)
	add_child(ground)
	_slab(Vector3(80, 0.02, 300), Vector3(0, -0.01, -40), Color(0.42, 0.5, 0.36))  # grass
	_slab(Vector3(9, 0.02, 300), Vector3(0, 0.0, -40), Color(0.2, 0.2, 0.22))  # road
	for i in range(6):  # crossing stripes
		_slab(Vector3(0.6, 0.02, 3.0), Vector3(-3.75 + i * 1.5, 0.005, 0), Color(0.9, 0.9, 0.88))
	var cam := Camera3D.new()
	cam.position = Vector3(10.0, 3.0, 4.0)
	add_child(cam)
	cam.look_at(Vector3(0, 0.5, -6.0))
	cam.fov = 60.0
	cam.current = true


func _slab(size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)


func _build_car() -> void:
	car = TrafficManager.DRIVABLE_CAR_SCENE.instantiate()
	car.position = Vector3(0, 0.6, CAR_START_Z)
	add_child(car)
	car.linear_velocity = Vector3(0, 0, -speed_kph / 3.6)
	car.override_throttle = 0.25


func _build_pedestrian() -> void:
	var w := RoadGraph.PedestrianWay.new()
	w.id = "lab_crossing"
	w.kind = "crossing"
	w.width_m = 3.0
	w.road_class = "footway"
	w.polyline = PackedVector3Array([Vector3(-12, 0, 0), Vector3(12, 0, 0)])
	var ways: Array[RoadGraph.PedestrianWay] = [w]
	peds = PedestrianManager.new()
	add_child(peds)  # loads the config
	peds.max_agents = 1  # the walker only: no spawning
	peds.setup(WalkGraph.build(ways))
	walker = Pedestrian.new()
	walker.path_id = 0
	walker.forward = true
	walker.speed = 1.3
	walker.lateral = 0.0
	walker.color = Color(0.3, 0.45, 0.8)
	# Start so the walker reaches the car's lane centre as the car arrives.
	var t_meet := (CAR_START_Z - CONTACT_Z) / (speed_kph / 3.6)
	walker.distance = maxf(12.0 - walker.speed * t_meet, 0.0)
	walker.transform = Transform3D(Basis(), peds.walk.paths[0].position_at(walker.distance))
	peds.agents.append(walker)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if peds != null:
		peds.anchors = PackedVector3Array([car.global_position])
	var v_kph := -car.linear_velocity.z * 3.6
	var z := car.global_position.z
	# Hold the set speed on the run-up, then coast through the crossing. Both runs (with and
	# without the walker) measure from the same point on the road, so the difference is the hit.
	car.override_throttle = (0.25 if v_kph < speed_kph else 0.0) if z > MEASURE_FROM_Z + 3.0 else 0.0
	if _hit_at < 0.0 and z <= MEASURE_FROM_Z:
		_hit_at = _elapsed
		_before_kph = v_kph
	if brake_after_hit and _hit_at >= 0.0 and _elapsed - _hit_at > 0.3 and v_kph > 1.0:
		car.override_brake = 1.0
	if _hit_at >= 0.0:
		if _elapsed - _hit_at <= MEASURE_S:
			_lowest_kph = minf(_lowest_kph, v_kph)
			if walker != null:
				var tv := peds.thrown_velocity(walker)
				_peak_ped_mps = maxf(_peak_ped_mps, tv.length())
				if OS.has_environment("PED_HIT_TRACE"):
					print("t+%.3f car %.1f km/h  person %s  thrown %.1f m/s" % [_elapsed - _hit_at, v_kph, walker.position(), tv.length()])
		elif result.is_empty():
			_finish()
	if exit_after_s > 0.0 and _elapsed >= exit_after_s:
		if result.is_empty():
			_finish()
		get_tree().quit()


func _finish() -> void:
	result = {
		"before_kph": _before_kph,
		"lowest_kph": _lowest_kph,
		"lost_kph": _before_kph - _lowest_kph,
		"person_peak_mps": _peak_ped_mps,
		"knocked_down": walker != null and walker.state != Pedestrian.State.WALKING,
	}
	print("ped-hit: car before %.1f km/h, lowest after %.1f km/h, lost %.1f km/h; person peak %.1f m/s, knocked down %s" % [
		result["before_kph"], result["lowest_kph"], result["lost_kph"], result["person_peak_mps"], result["knocked_down"]])
	finished.emit(result)
