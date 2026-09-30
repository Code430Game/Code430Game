extends Node3D
## Play testbed: loads the Ottawa map pack, builds all chunks (static load,
## streaming comes later), and spawns the local player on foot beside the
## placeholder car on the Queensway. Press Y (interact) to get in and out.
##
## Command line (after `--`): --benchmark=<seconds> records frame times with
## vsync off, prints a summary and quits; --autodrive holds the throttle;
## --preset=deck|high forces a graphics preset; --screenshot=<path> saves a PNG
## at the end of the benchmark.

const PACK_ID := "code430.ottawa-centretown"
const CAR_SCENE := preload("res://actors/vehicles/placeholder_car.tscn")
const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const ON_FOOT_OFFSET_M := 2.2
const BENCH_WARMUP_S := 3.0

@onready var _world: Node3D = $World
@onready var _camera: ChaseCamera = $ChaseCamera
@onready var _hud: Label = $HUD/Label
@onready var _prompt: Label = $HUD/Prompt
@onready var _graph_view: RoadGraphDebugView = $GraphView
@onready var _minimap: Minimap = $HUD/Minimap
@onready var _overview: OverviewMap = $OverviewMap
@onready var _pause_menu: PauseMenu = $PauseMenu
var _map_renderer: MapRenderer
var _traffic: TrafficManager
var _traffic_cap: int = -1

var _pack: MapPack
var _car: VehicleBody3D
var _player: Player
var _start_in_car: bool = false
var _bench_seconds: float = 0.0
var _bench_elapsed: float = 0.0
var _bench_frames: PackedFloat32Array = PackedFloat32Array()
var _bench_cpu: PackedFloat32Array = PackedFloat32Array()
var _bench_gpu: PackedFloat32Array = PackedFloat32Array()
var _autodrive: bool = false
var _screenshot_path: String = ""
var _start_position: Vector3 = Vector3.ZERO
var _bench_done: bool = false
var _autodrive_edge: RoadGraph.RoadEdge
var _autodrive_reverse: bool = false
var _autodrive_distance: float = 0.0
var _telemetry: bool = false
var _telemetry_next: float = 0.0
var _bumps: bool = false
var _last_vy: float = 0.0
const BUMP_THRESHOLD_MPS2 := 90.0
var _topdown: bool = false
var _topdown_height: float = 160.0
var _spawn_override: Vector3 = Vector3.INF
var _road_label: String = ""
var _road_label_next: float = 0.0
var _open_map_on_start: bool = false


func _ready() -> void:
	# The testbed itself keeps running while the overview map pauses the game, so the
	# HUD, benchmark, and screenshot logic work with the map open. Children that must
	# freeze are set pausable explicitly.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	_camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	_graph_view.process_mode = Node.PROCESS_MODE_PAUSABLE
	_parse_args()
	_pause_menu.overview_map = _overview
	_pause_menu.quit_requested.connect(func() -> void: get_tree().quit())
	var dir := PackLocator.find_pack(PACK_ID)
	if dir == "":
		_hud.text = "Map pack %s not found.\nSearched: %s" % [PACK_ID, "\n".join(PackLocator.search_dirs())]
		push_error(_hud.text)
		return
	_pack = MapPack.new()
	if not _pack.load(dir):
		_hud.text = "Failed to load pack at %s" % dir
		return
	var t0 := Time.get_ticks_msec()
	var stats := _pack.build_all_chunks(_world, true)
	print("testbed: built %s in %d ms" % [stats, Time.get_ticks_msec() - t0])
	_graph_view.set_graph(_pack.graph)
	_car = CAR_SCENE.instantiate()
	_car.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_car)
	var spawn := _pack.spawn_transform()
	var spawn_edge: RoadGraph.RoadEdge = _pack.spawn_edge()
	var spawn_reverse := false
	var spawn_distance := 20.0
	if _spawn_override != Vector3.INF:
		var hit := _pack.graph.nearest_edge(_spawn_override, 200.0)
		if not hit.is_empty():
			spawn = _spawn_on_edge(hit)
			spawn_edge = hit["edge"]
			spawn_distance = RoadGeometry.length_xz(spawn_edge.polyline.slice(0, int(hit["segment"]) + 1)) + float(hit["t"]) if hit.has("t") else 0.0
	_car.recover_callback = _recover_car
	_car.global_transform = spawn
	_car.set_spawn(spawn)
	_camera.target = _car
	_camera.global_position = spawn.origin + spawn.basis.z * 8.0 + Vector3.UP * 3.0
	_start_position = spawn.origin
	_player = PLAYER_SCENE.instantiate()
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_player)
	_player.global_position = spawn.origin - spawn.basis.x * ON_FOOT_OFFSET_M + Vector3.UP * 0.2
	_player.entered_vehicle.connect(_on_entered_vehicle)
	_player.exited_vehicle.connect(_on_exited_vehicle)
	_player.take_vehicle_requested.connect(_on_take_vehicle_requested)
	if _start_in_car or _autodrive:
		_player.enter_vehicle(_car)
	else:
		_player.activate_camera()
	_setup_maps()
	_setup_traffic()
	_autodrive_edge = spawn_edge
	_autodrive_reverse = spawn_reverse
	_autodrive_distance = spawn_distance
	if _bench_seconds > 0.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _on_entered_vehicle(car: VehicleBody3D) -> void:
	_camera.target = car
	_camera.global_position = car.global_position + car.global_basis.z * 7.5 + Vector3.UP * 3.0
	_camera.current = true
	_minimap.player = car
	_overview.player = car


func _on_take_vehicle_requested(traffic_body: Node3D) -> void:
	if _traffic == null or not (traffic_body is TrafficCar):
		return
	var car := _traffic.take_car(traffic_body as TrafficCar)
	if car != null:
		_player.enter_vehicle(car)


func _on_exited_vehicle(_car_left: VehicleBody3D) -> void:
	_player.activate_camera()
	_minimap.player = _player
	_overview.player = _player


func _setup_traffic() -> void:
	var t0 := Time.get_ticks_msec()
	var lane_graph := LaneGraph.build(_pack.graph, _pack.junctions)
	_traffic = TrafficManager.new()
	_traffic.name = "Traffic"
	_traffic.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_traffic)
	_traffic.setup(lane_graph)
	if _traffic_cap >= 0:
		_traffic.max_agents = _traffic_cap
	_traffic.enabled = _traffic_cap != 0
	print("traffic: %d lane paths in %d ms, cap %d" % [lane_graph.paths.size(), Time.get_ticks_msec() - t0, _traffic.max_agents])


func _setup_maps() -> void:
	_map_renderer = MapRenderer.new()
	var b := Projector_bounds()
	_map_renderer.set_bounds(b)
	_minimap.renderer = _map_renderer
	_minimap.player = Players.local_controlled_body()
	_overview.renderer = _map_renderer
	_overview.graph = _pack.graph
	_overview.player = Players.local_controlled_body()
	var t0 := Time.get_ticks_msec()
	await _map_renderer.render(self, _pack.graph, _pack.water_polygons, _pack.buildings)
	print("map texture %s rendered in %d ms" % [_map_renderer.size_px, Time.get_ticks_msec() - t0])
	if _open_map_on_start:
		_overview.open()


## Local-metre bounds of the loaded pack: min_x, min_z, max_x, max_z, from the terrain chunks.
func Projector_bounds() -> Vector4:
	var min_c := Vector2i(1 << 30, 1 << 30)
	var max_c := Vector2i(-(1 << 30), -(1 << 30))
	for c in _pack.chunk_coords():
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	var s := RoadGeometry.CHUNK_SIZE_M
	return Vector4(min_c.x * s, min_c.y * s, (max_c.x + 1) * s, (max_c.y + 1) * s)


## Transform on the road surface at the nearest-edge hit, facing along the edge.
func _spawn_on_edge(hit: Dictionary) -> Transform3D:
	var e: RoadGraph.RoadEdge = hit["edge"]
	var i: int = hit["segment"]
	var forward := e.polyline[i + 1] - e.polyline[i]
	forward.y = 0.0
	if forward.length_squared() < 1e-6:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	# Sit in the first forward lane (right of the divider), not on the centreline.
	var lanes_total := e.lanes_forward + e.lanes_backward
	var lane_w := e.width_m / maxf(lanes_total, 1)
	var divider := e.width_m * 0.5 - e.lanes_forward * lane_w
	var right := Vector3(-forward.z, 0.0, forward.x)
	var offset := right * (divider + 0.5 * lane_w)
	return Transform3D(Basis.looking_at(forward, Vector3.UP), hit["point"] + offset + Vector3.UP * 1.0)


## Puts a rolled or lost car back on the nearest road, or at the spawn if none is near.
func _recover_car(car: VehicleBody3D) -> void:
	var hit := _pack.graph.nearest_edge(car.global_position, 80.0)
	if hit.is_empty() or car.global_position.y < car.world_floor_y:
		car.reset_to_spawn()
		return
	car.global_transform = _spawn_on_edge(hit)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO


func _bench_elapsed_hud(delta: float) -> void:
	_road_label_next -= delta
	if _road_label_next > 0.0:
		return
	_road_label_next = 0.25
	var body: Node3D = Players.local_controlled_body()
	var hit := _pack.graph.nearest_edge(body.global_position, 40.0)
	if hit.is_empty():
		_road_label = "off road"
		return
	var e: RoadGraph.RoadEdge = hit["edge"]
	var name := e.name if e.name != "" else e.road_class.replace("_", " ")
	_road_label = "%s (%s%s)" % [name, e.road_class, ", one-way" if e.oneway else ""]


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--benchmark="):
			_bench_seconds = float(arg.get_slice("=", 1))
		elif arg == "--autodrive":
			_autodrive = true
		elif arg.begins_with("--preset="):
			Settings.apply_preset(arg.get_slice("=", 1))
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.get_slice("=", 1)
		elif arg == "--telemetry":
			_telemetry = true
		elif arg == "--bumps":
			_bumps = true
		elif arg.begins_with("--topdown"):
			_topdown = true
			if arg.contains("="):
				_topdown_height = float(arg.get_slice("=", 1))
		elif arg == "--graph":
			_graph_view.visible = true
		elif arg == "--map":
			_open_map_on_start = true
		elif arg == "--drive":
			_start_in_car = true
		elif arg.begins_with("--traffic="):
			_traffic_cap = int(arg.get_slice("=", 1))
		elif arg.begins_with("--spawn="):
			var parts := arg.get_slice("=", 1).split(",")
			if parts.size() == 2:
				_spawn_override = Vector3(float(parts[0]), 0.0, float(parts[1]))


func _process(delta: float) -> void:
	if _traffic != null and _car != null:
		var body: Node3D = Players.local_controlled_body()
		_traffic.anchors = PackedVector3Array([body.global_position])
		_traffic.obstacles = [body]
		if _traffic.lanes != null and _graph_view.visible != (_traffic._debug_mesh != null and _traffic._debug_mesh.visible):
			_traffic.set_debug_visible(_graph_view.visible)
	if _car != null and _player != null:
		_bench_elapsed_hud(delta)
		var body: Node3D = Players.local_controlled_body()
		if _player.is_driving():
			_hud.text = "%d km/h\nx %.0f  y %.1f  z %.0f     RT accelerate, LT brake/reverse, RB handbrake, Y get out, Back map, Menu pause" % [
				int(_car.speed_kph()), body.global_position.x, body.global_position.y, body.global_position.z,
			]
			_prompt.text = ""
		else:
			_hud.text = "on foot\nx %.0f  y %.1f  z %.0f     left stick walk, L3 run, A jump, right stick look, Y get in, Back map, Menu pause" % [
				body.global_position.x, body.global_position.y, body.global_position.z,
			]
			_prompt.text = "Y  get in" if _player.nearest_vehicle() != null else ""
	if _autodrive and _car != null:
		_autodrive_step()
	if _telemetry and _car != null and _bench_elapsed >= _telemetry_next:
		_telemetry_next += 1.0
		print("t=%.0f pos=(%.0f, %.1f, %.0f) speed=%.0f steer=%.2f edge=%s s=%.0f up=%.2f road=%s driving=%s driver=%d traffic=%d" % [
			_bench_elapsed, _car.global_position.x, _car.global_position.y, _car.global_position.z,
			_car.speed_kph(), _car.steering, _autodrive_edge.id if _autodrive_edge else "-", _autodrive_distance,
			_car.global_basis.y.y, _road_label, _player.is_driving(), _car.driver_peer_id, _traffic.active_count() if _traffic else 0,
		])
	if _bumps and _car != null and _player != null and _player.is_driving() and delta > 0.0:
		var vy := _car.linear_velocity.y
		var accel := (vy - _last_vy) / delta
		_last_vy = vy
		if absf(accel) > BUMP_THRESHOLD_MPS2 and _bench_elapsed > 1.0:
			var here := _pack.graph.nearest_edge(_car.global_position, 30.0)
			var eid: String = here["edge"].id if not here.is_empty() else "-"
			var ename: String = here["edge"].name if not here.is_empty() else ""
			print("BUMP t=%.1f accel_y=%.0f m/s2 vy=%.1f pos=(%.0f, %.1f, %.0f) speed=%.0f edge=%s %s" % [
				_bench_elapsed, accel, vy, _car.global_position.x, _car.global_position.y, _car.global_position.z, _car.speed_kph(), eid, ename,
			])
	if _topdown and _car != null:
		_camera.set_process(false)
		_camera.global_position = _car.global_position + Vector3(0, _topdown_height, 0.01)
		_camera.look_at(_car.global_position, Vector3.UP)
	if _bench_seconds > 0.0:
		_bench_elapsed += delta
		if _bench_elapsed > BENCH_WARMUP_S:
			_bench_frames.append(delta * 1000.0)
			var rid := get_viewport().get_viewport_rid()
			_bench_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			_bench_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		if _bench_elapsed >= _bench_seconds + BENCH_WARMUP_S and not _bench_done:
			_bench_done = true
			_print_benchmark()
			if _screenshot_path != "":
				await RenderingServer.frame_post_draw
				var err := get_viewport().get_texture().get_image().save_png(_screenshot_path)
				print("screenshot: %s (%s)" % [_screenshot_path, error_string(err)])
			get_tree().quit()


func _print_benchmark() -> void:
	var sorted := _bench_frames.duplicate()
	sorted.sort()
	var sum := 0.0
	for f in sorted:
		sum += f
	var n := sorted.size()
	if n == 0:
		print("benchmark: no frames recorded")
		return
	var travelled := Players.local_controlled_body().global_position.distance_to(_start_position) if _car != null else 0.0
	var cpu_sum := 0.0
	var gpu_sum := 0.0
	for v in _bench_cpu:
		cpu_sum += v
	for v in _bench_gpu:
		gpu_sum += v
	var render_note := "render cpu %.2f ms gpu %.2f ms (measured, pacing-independent)" % [cpu_sum / maxf(_bench_cpu.size(), 1), gpu_sum / maxf(_bench_gpu.size(), 1)]
	print("benchmark: %d frames, avg %.2f ms, p50 %.2f ms, p95 %.2f ms, p99 %.2f ms, max %.2f ms, preset %s, deck detected %s, %s, travelled %.0f m, draw calls %d, %s" % [
		n, sum / n, sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1],
		Settings.current_preset_name, Settings.is_steam_deck, "autodrive" if _autodrive else "static", travelled,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		RenderingServer.get_video_adapter_name(),
	])
	print("benchmark: %s" % render_note)
	if _traffic != null:
		print("benchmark: traffic agents %d, physics process %.2f ms" % [_traffic.active_count(), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])


const AUTODRIVE_LOOKAHEAD_M := 14.0
const AUTODRIVE_THROTTLE := 0.6
const AUTODRIVE_STEER_GAIN := 1.4
## Autodrive aims for this fraction of the edge's speed limit.
const AUTODRIVE_SPEED_FRACTION := 0.9


## Pure-pursuit along the road graph: steer toward a point ahead on the current
## edge, hop to the straightest outgoing edge at its end.
func _autodrive_step() -> void:
	if _autodrive_edge == null:
		return
	var pl := _autodrive_edge.polyline
	if _autodrive_reverse:
		pl = pl.duplicate()
		pl.reverse()
	var car_pos := _car.global_position
	# Advance the tracked distance to the closest point ahead of the car.
	var total := RoadGeometry.length_xz(pl)
	var probe := _autodrive_distance
	var best_d := INF
	var best_s := _autodrive_distance
	while probe <= total:
		var q := RoadGeometry.point_at(pl, probe)
		var d := Vector2(q.x - car_pos.x, q.z - car_pos.z).length()
		if d < best_d:
			best_d = d
			best_s = probe
		probe += 5.0
	_autodrive_distance = best_s
	var target_s := _autodrive_distance + AUTODRIVE_LOOKAHEAD_M
	if target_s >= total:
		var end_node := _autodrive_edge.to_node if not _autodrive_reverse else _autodrive_edge.from_node
		var next := _next_edge(end_node, _autodrive_edge)
		if next == null:
			_car.override_throttle = 0.0
			return
		_autodrive_reverse = next.to_node == end_node
		_autodrive_edge = next
		_autodrive_distance = 0.0
		target_s = minf(AUTODRIVE_LOOKAHEAD_M, RoadGeometry.length_xz(next.polyline))
		pl = next.polyline
		if _autodrive_reverse:
			pl = pl.duplicate()
			pl.reverse()
	var target := RoadGeometry.point_at(pl, target_s)
	var local := _car.to_local(target)
	var angle := atan2(-local.x, -local.z)  # forward is -z; positive = target is to the left
	_car.override_steer = clampf(angle * AUTODRIVE_STEER_GAIN, -1.0, 1.0)
	var limit_kph := float(_autodrive_edge.speed_kph) * AUTODRIVE_SPEED_FRACTION
	_car.override_throttle = AUTODRIVE_THROTTLE if _car.speed_kph() < limit_kph else 0.0


## The outgoing edge at a node that best continues the direction of `from`.
func _next_edge(node_id: String, from: RoadGraph.RoadEdge) -> RoadGraph.RoadEdge:
	var arrive := -_pack.graph.direction_from(from, node_id)
	var best: RoadGraph.RoadEdge = null
	var best_dot := -2.0
	for eid in _pack.graph.incident(node_id):
		if eid == from.id:
			continue
		var e: RoadGraph.RoadEdge = _pack.graph.edges[eid]
		if e.oneway and e.to_node == node_id:
			continue  # would be driving against a one-way
		var dot := arrive.dot(_pack.graph.direction_from(e, node_id))
		if dot > best_dot:
			best_dot = dot
			best = e
	return best
