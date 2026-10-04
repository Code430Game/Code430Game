class_name TrafficHitLab
extends Node3D
## Repeatable crashes between the player's car and traffic, through the real TrafficManager on
## a straight road. Prints one "traffic-hit:" line and emits `finished`.
##
## --scenario=rear: the player's car at 50 km/h into a stopped traffic sedan.
## --scenario=chain: the same, into a queue of two stopped sedans nose to tail.
## --scenario=recover: a traffic car knocked 3.9 m off its lane sits against the far side of
##   the player's car, parked beside the lane, when its hit window ends; the manager puts it
##   back on its lane, through the player's car.
## --scenario=nudge: a traffic car at 50 km/h that hasn't seen the parked player's car drives
##   into its back (in play: lane changes, turns and sideswipes the headway rule misses).
## --scenario=wedge: the player's car stands still; a traffic car stops at the road's dead end
##   just ahead of it and a second one comes up from behind, keeping its usual gap to the first
##   car, which leaves no room for the player's car between them.
##
## Run: Godot --path game res://scenes/traffic_hit_lab.tscn -- --scenario=wedge --exit-after=10

signal finished(result: Dictionary)

const MEASURE_S := 6.0  # longer than the traffic hit window (3 s), to see what happens when it ends

var scenario: String = "rear"
var exit_after_s: float = -1.0
var push: bool = false  # --push: full throttle through the contact, like a player shoving
var follower_mps: float = 8.0  # --follower-kph=N: how fast the wedge's second car comes up
var car: VehicleBody3D
var traffic: TrafficManager
var result: Dictionary = {}
var _elapsed: float = 0.0
var _contact_at: float = -1.0
var _before_kph: float = -1.0
var _lowest_kph: float = INF
var _peak_body_mps: float = 0.0
var _peak_car_mps: float = 0.0
var _car_start: Vector3
var _max_displacement: float = 0.0
var _max_height: float = 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.get_slice("=", 1)
		elif arg.begins_with("--exit-after="):
			exit_after_s = float(arg.get_slice("=", 1))
		elif arg == "--push":
			push = true
		elif arg.begins_with("--follower-kph="):
			follower_mps = float(arg.get_slice("=", 1)) / 3.6
	_build_world()
	_build_traffic()
	_build_car()


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
	box.size = Vector3(500, 1, 80)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	add_child(ground)
	for spec: Array in [[Vector3(500, 0.02, 80), Vector3(0, -0.01, 0), Color(0.42, 0.5, 0.36)], [Vector3(500, 0.02, 8), Vector3(0, 0.0, 0), Color(0.2, 0.2, 0.22)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec[2]
		bm.material = mat
		mi.mesh = bm
		mi.position = spec[1]
		add_child(mi)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(-4.0, 6.0, 16.0)
	cam.look_at(Vector3(2.0, 0.8, 0.0))
	cam.fov = 55.0
	cam.current = true


## Traffic runs +x along one lane. Rear: a long road with traffic held still. Wedge: the road
## ends at x = 6, so the lead car stops there.
func _build_traffic() -> void:
	var end_x := 6.0 if scenario == "wedge" else 200.0
	var pl := [[-200.0, 0.0, 0.0], [end_x, 0.0, 0.0]]
	var nodes := [
		{"id": "a", "position": pl[0], "ground_y": 0, "junction_type": "junction"},
		{"id": "b", "position": pl[1], "ground_y": 0, "junction_type": "junction"},
	]
	var edges := [{"id": "w1.0", "from": "a", "to": "b", "polyline": pl, "class": "secondary", "lanes_forward": 1, "lanes_backward": 0,
		"oneway": true, "speed_kph": 50, "width_m": 7.0, "layer": 0, "bridge": false, "tunnel": false, "name": "lab",
		"osm_way_id": 1, "defaulted_fields": [], "access": null, "length_m": 200.0 + end_x, "bus": "", "bus_lane": -1}]
	var graph := RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": [], "bus_stops": []})
	traffic = TrafficManager.new()
	add_child(traffic)  # loads the config
	traffic.config["spawns_per_interval"] = 0
	traffic.config["accel_mps2"] = 6.0  # the follower keeps its speed up to the contact
	if scenario in ["rear", "chain", "recover"]:
		traffic.config["speed_fraction"] = 0.0  # everyone holds still
	traffic.setup(LaneGraph.build(graph, JunctionBuilder.build_all(graph)))
	var lane: LaneGraph.LanePath = traffic.lanes.paths[0]
	if scenario == "wedge":
		_add_agent(lane, lane.length - 0.5, 0.0)  # the lead car, at the dead end
		_add_agent(lane, lane.length - 60.0, follower_mps)  # the follower, coming up behind
	elif scenario == "nudge":
		_add_agent(lane, lane.closest(Vector3(-70, 0, 0)).x, 50.0 / 3.6)
	elif scenario == "chain":  # a queue of two: the one we hit is shoved into the one ahead
		_add_agent(lane, lane.closest(Vector3.ZERO).x, 0.0)
		_add_agent(lane, lane.closest(Vector3(5.6, 0, 0)).x, 0.0)
	else:
		_add_agent(lane, lane.closest(Vector3.ZERO).x, 0.0)


func _add_agent(lane: LaneGraph.LanePath, distance: float, speed: float) -> void:
	var a := TrafficAgent.new()
	a.vehicle_id = "sedan"
	a.length_m = float(VehicleCatalogue.entry("sedan")["dims"]["length_m"])
	a.color = Color(0.15, 0.3, 0.6)
	a.path_id = lane.id
	a.distance = distance
	a.speed = speed
	a.transform = Transform3D(Basis.looking_at(lane.direction_at(distance), Vector3.UP), lane.position_at(distance))
	traffic.agents.append(a)


func _build_car() -> void:
	car = TrafficManager.DRIVABLE_CAR_SCENE.instantiate()
	var start := Vector3(-70.0, 0.6, 0.0) if scenario in ["rear", "chain"] else Vector3(-0.2, 0.6, 0.0)
	if scenario == "recover":
		start = Vector3(0.0, 0.6, -1.95)  # parked beside the lane
	add_child(car)
	car.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), start)
	if scenario in ["rear", "chain"]:
		car.linear_velocity = Vector3(50.0 / 3.6, 0, 0)
		car.override_throttle = 0.25
	_car_start = start


func _physics_process(delta: float) -> void:
	_elapsed += delta
	traffic.anchors = PackedVector3Array([car.global_position])
	var v_kph := car.linear_velocity.x * 3.6
	if scenario in ["rear", "chain"] and _contact_at < 0.0:
		car.override_throttle = 0.25 if v_kph < 50.0 else 0.0
		if car.global_position.x > -8.0:
			car.override_throttle = 0.0
	if push and _contact_at >= 0.0:
		car.override_throttle = 1.0
	if scenario == "recover" and _elapsed > 0.5 and _contact_at < 0.0:
		# Knock the car off its lane by hand: retired, dynamic, 1.9 m to the side, against our car.
		var a: TrafficAgent = traffic.agents[0]
		if a.body != null and not a.retired:
			a.retired = true
			a.resting = false
			a.hit_timer = 0.5
			a.body.freeze = false
			a.body.global_position = a.body.global_position + Vector3(0, 0, -3.9)  # beyond our car, against its far side
			a.transform = a.body.global_transform
			_contact_at = _elapsed
	if _contact_at < 0.0:
		_before_kph = v_kph
		for a in traffic.agents:
			if a.position().distance_to(car.global_position) < (a.length_m + 4.6) * 0.5 + 0.4:
				_contact_at = _elapsed
	if _contact_at >= 0.0 and _elapsed - _contact_at <= MEASURE_S:
		_lowest_kph = minf(_lowest_kph, v_kph)
		_peak_car_mps = maxf(_peak_car_mps, car.linear_velocity.length())
		_peak_body_mps = maxf(_peak_body_mps, car.linear_velocity.length())
		for a in traffic.agents:
			if a.body != null and not a.body.freeze:
				_peak_body_mps = maxf(_peak_body_mps, a.body.linear_velocity.length())
		_max_height = maxf(_max_height, car.global_position.y)
		var flat := car.global_position - _car_start
		_max_displacement = maxf(_max_displacement, Vector2(flat.y, flat.z).length())  # off the lane's line
	elif _contact_at >= 0.0 and result.is_empty():
		_finish()
	if OS.has_environment("TRAFFIC_HIT_TRACE") and _contact_at >= 0.0 and _elapsed - _contact_at <= MEASURE_S and int(_elapsed * 60) % 10 == 0:
		var line := "t+%.2f car x %.2f v %.1f |" % [_elapsed - _contact_at, car.global_position.x, car.linear_velocity.length()]
		for a in traffic.agents:
			line += " agent x %.2f retired %s body %s" % [a.position().x, a.retired, "none" if a.body == null else ("frozen" if a.body.freeze else "dyn v %.1f" % a.body.linear_velocity.length())]
		print(line)
	if exit_after_s > 0.0 and _elapsed >= exit_after_s:
		if result.is_empty():
			_finish()
		get_tree().quit()


func _finish() -> void:
	result = {
		"scenario": scenario,
		"contact": _contact_at >= 0.0,
		"before_kph": _before_kph,
		"lowest_kph": _lowest_kph,
		"peak_car_mps": _peak_car_mps,
		"peak_body_mps": _peak_body_mps,
		"max_height_m": _max_height,
		"off_line_m": _max_displacement,
	}
	print("traffic-hit: %s, contact %s, player car %.1f -> lowest %.1f km/h, peak speed car %.1f m/s, any body %.1f m/s, highest %.2f m, off line %.2f m" % [
		scenario, result["contact"], _before_kph, _lowest_kph, _peak_car_mps, _peak_body_mps, _max_height, _max_displacement])
	finished.emit(result)
