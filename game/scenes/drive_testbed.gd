extends Node3D
## Drivable testbed: loads the Ottawa map pack, builds all chunks (static load,
## streaming comes later), spawns the placeholder car on the Queensway.
##
## Command line (after `--`): --benchmark=<seconds> records frame times with
## vsync off, prints a summary and quits; --autodrive holds the throttle;
## --preset=deck|high forces a graphics preset; --screenshot=<path> saves a PNG
## at the end of the benchmark.

const PACK_ID := "code430.ottawa-centretown"
const CAR_SCENE := preload("res://actors/vehicles/placeholder_car.tscn")
const BENCH_WARMUP_S := 3.0

@onready var _world: Node3D = $World
@onready var _camera: ChaseCamera = $ChaseCamera
@onready var _hud: Label = $HUD/Label
@onready var _graph_view: RoadGraphDebugView = $GraphView

var _pack: MapPack
var _car: VehicleBody3D
var _bench_seconds: float = 0.0
var _bench_elapsed: float = 0.0
var _bench_frames: PackedFloat32Array = PackedFloat32Array()
var _autodrive: bool = false
var _screenshot_path: String = ""
var _start_position: Vector3 = Vector3.ZERO
var _bench_done: bool = false
var _autodrive_edge: RoadGraph.RoadEdge
var _autodrive_reverse: bool = false
var _autodrive_distance: float = 0.0
var _telemetry: bool = false
var _telemetry_next: float = 0.0
var _topdown: bool = false
var _topdown_height: float = 160.0
var _spawn_override: Vector3 = Vector3.INF
var _road_label: String = ""
var _road_label_next: float = 0.0


func _ready() -> void:
	_parse_args()
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
	add_child(_car)
	var spawn := _pack.spawn_transform()
	if _spawn_override != Vector3.INF:
		var hit := _pack.graph.nearest_edge(_spawn_override, 200.0)
		if not hit.is_empty():
			spawn = _spawn_on_edge(hit)
	_car.recover_callback = _recover_car
	_car.global_transform = spawn
	_car.set_spawn(spawn)
	_camera.target = _car
	_camera.global_position = spawn.origin + spawn.basis.z * 8.0 + Vector3.UP * 3.0
	_start_position = spawn.origin
	_autodrive_edge = _pack.spawn_edge()
	_autodrive_distance = 20.0
	if _bench_seconds > 0.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


## Transform on the road surface at the nearest-edge hit, facing along the edge.
func _spawn_on_edge(hit: Dictionary) -> Transform3D:
	var e: RoadGraph.RoadEdge = hit["edge"]
	var i: int = hit["segment"]
	var forward := e.polyline[i + 1] - e.polyline[i]
	forward.y = 0.0
	if forward.length_squared() < 1e-6:
		forward = Vector3.FORWARD
	return Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), hit["point"] + Vector3.UP * 1.0)


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
	var hit := _pack.graph.nearest_edge(_car.global_position, 40.0)
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
		elif arg.begins_with("--topdown"):
			_topdown = true
			if arg.contains("="):
				_topdown_height = float(arg.get_slice("=", 1))
		elif arg == "--graph":
			_graph_view.visible = true
		elif arg.begins_with("--spawn="):
			var parts := arg.get_slice("=", 1).split(",")
			if parts.size() == 2:
				_spawn_override = Vector3(float(parts[0]), 0.0, float(parts[1]))


func _process(delta: float) -> void:
	if _car != null:
		_bench_elapsed_hud(delta)
		_hud.text = "%d km/h   %s\nx %.0f  y %.1f  z %.0f     RT accelerate, LT brake/reverse, RB handbrake, Back+Y reset, Back+B road graph, Back+X stats" % [
			int(_car.speed_kph()), _road_label, _car.global_position.x, _car.global_position.y, _car.global_position.z,
		]
	if _autodrive and _car != null:
		_autodrive_step()
	if _telemetry and _car != null and _bench_elapsed >= _telemetry_next:
		_telemetry_next += 1.0
		print("t=%.0f pos=(%.0f, %.1f, %.0f) speed=%.0f steer=%.2f edge=%s s=%.0f up=%.2f" % [
			_bench_elapsed, _car.global_position.x, _car.global_position.y, _car.global_position.z,
			_car.speed_kph(), _car.steering, _autodrive_edge.id if _autodrive_edge else "-", _autodrive_distance,
			_car.global_basis.y.y,
		])
	if _topdown and _car != null:
		_camera.set_process(false)
		_camera.global_position = _car.global_position + Vector3(0, _topdown_height, 0.01)
		_camera.look_at(_car.global_position, Vector3.UP)
	if Input.is_action_just_pressed("pause"):
		get_tree().quit()
	if _bench_seconds > 0.0:
		_bench_elapsed += delta
		if _bench_elapsed > BENCH_WARMUP_S:
			_bench_frames.append(delta * 1000.0)
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
	var travelled := _car.global_position.distance_to(_start_position) if _car != null else 0.0
	print("benchmark: %d frames, avg %.2f ms, p50 %.2f ms, p95 %.2f ms, p99 %.2f ms, max %.2f ms, preset %s, deck detected %s, %s, travelled %.0f m, draw calls %d, %s" % [
		n, sum / n, sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1],
		Settings.current_preset_name, Settings.is_steam_deck, "autodrive" if _autodrive else "static", travelled,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		RenderingServer.get_video_adapter_name(),
	])


const AUTODRIVE_LOOKAHEAD_M := 18.0
const AUTODRIVE_THROTTLE := 0.6
const AUTODRIVE_STEER_GAIN := 1.4


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
	_car.override_throttle = AUTODRIVE_THROTTLE


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
