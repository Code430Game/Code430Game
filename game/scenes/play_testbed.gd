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
@onready var _creator: CharacterCreator = $CharacterCreator
var _billboards: Billboards = null
const SESSION_SEED := 430  # until sessions carry their own seed
var _map_renderer: MapRenderer
var _traffic: TrafficManager
var _traffic_cap: int = -1
var _peds: PedestrianManager
var _peds_cap: int = -1
var _player_sync: PlayerSync
var _world_sync: WorldSync
var _host_port: int = -1  # --host[=port]
var _join_address: String = ""  # --join=address[:port]
var _spawn_transform: Transform3D
var _keyboard: bool = false  # last input came from keyboard or mouse: show those hints
var _day_night: DayNight
var _vehicle_audio: VehicleAudio
var _ambience: AmbienceAudio
var _mute: bool = false
var _start_hour: float = -1.0  # --time=HH
var _day_minutes: float = -1.0  # --day-minutes=N

var _pack: MapPack
var _streamer: ChunkStreamer
var _first_playable_ms: int = -1
var _car: VehicleBody3D
var _player: Player
var _start_in_car: bool = false
var _bench_seconds: float = 0.0
var _bench_elapsed: float = 0.0
var _bench_frames: PackedFloat32Array = PackedFloat32Array()
var _bench_cpu: PackedFloat32Array = PackedFloat32Array()
var _bench_gpu: PackedFloat32Array = PackedFloat32Array()
var _bench_physics: PackedFloat32Array = PackedFloat32Array()  # physics process ms per frame after warm-up
var _autodrive: bool = false
var _screenshot_path: String = ""
var _open_creator_at_start: bool = false  # --creator: open the character creator once loaded (screenshots)
var _free_camera: PackedFloat64Array = PackedFloat64Array()  # --camera=px,py,pz,tx,ty,tz: fixed camera for screenshots
var _fixed_cam: Camera3D = null
enum Headlights { AUTO, ON, OFF }
var _headlights: int = Headlights.AUTO  # D-pad up / H cycles auto (dusk to dawn), on, off
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
	_pause_menu.character_requested.connect(_open_creator)
	_creator.profile_changed.connect(func(p: Dictionary) -> void: if _player != null: _player.apply_profile(p))
	_creator.closed.connect(_on_creator_closed)
	_pause_menu.host_requested.connect(_host_game)
	_pause_menu.join_requested.connect(_join_game)
	Session.peer_joined.connect(func(_id: int, _info: Dictionary) -> void: _refresh_session_status())
	Session.peer_left.connect(func(_id: int) -> void: _refresh_session_status())
	Session.joined.connect(_on_joined)
	Session.refused.connect(func(reason: String) -> void: _pause_menu.set_status("join refused: " + reason); _set_mirror(false))
	Session.session_ended.connect(func() -> void: _pause_menu.set_status("offline"); _set_mirror(false))
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
	_streamer = ChunkStreamer.new()
	_streamer.name = "Streamer"
	_streamer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_streamer)
	_streamer.setup(_pack, _world)
	print("testbed: streamer ready (%d chunks indexed, glb cache %s) in %d ms" % [_pack.chunk_coords().size(), _streamer.use_glb, Time.get_ticks_msec() - t0])
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
	var t_ring := Time.get_ticks_msec()
	var ring := _streamer.build_now(spawn.origin)
	_first_playable_ms = Time.get_ticks_msec() - t0
	print("testbed: spawn ring %d chunks in %d ms; first playable at %d ms" % [ring, Time.get_ticks_msec() - t_ring, _first_playable_ms])
	_spawn_transform = spawn
	_car.recover_callback = _recover_car
	_car.global_transform = spawn
	_car.set_spawn(spawn)
	_camera.target = _car
	_camera.global_position = spawn.origin + spawn.basis.z * 8.0 + Vector3.UP * 3.0
	_start_position = spawn.origin
	_player = PLAYER_SCENE.instantiate()
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	_player.profile = CharacterStore.last_or_random()
	Session.local_profile = _player.profile
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
	_setup_pedestrians()
	_setup_day_night()
	_setup_audio()
	_setup_net()
	_setup_billboards()
	ContentMode.mode_changed.connect(func(_id: String) -> void: _refresh_session_status())
	if _open_creator_at_start:
		get_tree().create_timer(1.5).timeout.connect(_open_creator)
	if _free_camera.size() == 6:
		var cam := Camera3D.new()
		cam.far = 8000.0
		add_child(cam)
		cam.global_position = Vector3(_free_camera[0], _free_camera[1], _free_camera[2])
		cam.look_at(Vector3(_free_camera[3], _free_camera[4], _free_camera[5]), Vector3.UP)
		cam.current = true
		_fixed_cam = cam
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
	if Session.is_client():
		_world_sync.request_take(traffic_body.global_position)  # the host owns the car; answer in _on_take_granted
		return
	var car := _traffic.take_car(traffic_body as TrafficCar)
	if car != null:
		_player.enter_vehicle(car)


func _on_take_granted(t: Transform3D, color: Color) -> void:
	var car: VehicleBody3D = TrafficManager.DRIVABLE_CAR_SCENE.instantiate()
	car.set("body_color", color)
	add_child(car)
	car.global_transform = t.translated_local(Vector3(0.0, 0.3, 0.0))
	car.set_spawn(car.global_transform)
	_player.enter_vehicle(car)


func _on_exited_vehicle(_car_left: VehicleBody3D) -> void:
	_player.activate_camera()
	_minimap.player = _player
	_overview.player = _player


func _setup_day_night() -> void:
	_day_night = DayNight.new()
	_day_night.name = "DayNight"
	_day_night.process_mode = Node.PROCESS_MODE_PAUSABLE
	if _start_hour >= 0.0:
		_day_night.load_config()
		_day_night.config["start_hour"] = _start_hour
	if _day_minutes > 0.0:
		if _day_night.config.is_empty():
			_day_night.load_config()
		_day_night.config["day_minutes"] = _day_minutes
	add_child(_day_night)
	_day_night.setup($Sun as DirectionalLight3D, ($WorldEnvironment as WorldEnvironment).environment)
	_day_night.register_shader(_pack.building_material as ShaderMaterial)
	_day_night.register_emissive(CarMesh.light_material(), CarMesh.LIGHT_NIGHT_ENERGY)
	_day_night.register_emissive(CarMesh.tail_material(), CarMesh.LIGHT_NIGHT_ENERGY * 0.6)
	if _traffic != null and _traffic.tail_material != null:
		_day_night.register_shader(_traffic.tail_material)
	_day_night.register_emissive(SignalHeads.head_material(), SignalHeads.HEAD_NIGHT_ENERGY)
	var preset: Dictionary = Settings.presets.get(Settings.current_preset_name, {})
	_car.add_headlights(bool(preset.get("headlight_shadows", false)))


func _setup_audio() -> void:
	if _mute:
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	_vehicle_audio = VehicleAudio.new()
	_vehicle_audio.name = "VehicleAudio"
	_vehicle_audio.car = _car
	_car.add_child(_vehicle_audio)
	_car.impacted.connect(func(speed: float) -> void: _vehicle_audio.impact(speed))
	_ambience = AmbienceAudio.new()
	_ambience.name = "Ambience"
	_ambience.traffic = _traffic
	add_child(_ambience)


func _setup_net() -> void:
	Session.local_manifest = _pack.manifest_summary()
	_player_sync = PlayerSync.new()
	_player_sync.name = "PlayerSync"
	_player_sync.player = _player
	_player_sync.remote_parent = _world
	add_child(_player_sync)
	_world_sync = WorldSync.new()
	_world_sync.name = "WorldSync"
	_world_sync.traffic = _traffic
	_world_sync.peds = _peds
	_world_sync.player_sync = _player_sync
	_world_sync.day_night = _day_night
	_world_sync.take_granted.connect(_on_take_granted)
	if _traffic != null:
		_traffic.mirror_hit.connect(func(p: Vector3, v: Vector3) -> void: _world_sync.report_hit(p, v))
	add_child(_world_sync)
	if _host_port > 0:
		_host_game(_host_port)
	elif _join_address != "":
		_join_game(_join_address)


func _setup_billboards() -> void:
	if _pack.ads.is_empty():
		return
	_billboards = Billboards.new()
	_billboards.name = "Billboards"
	_billboards.process_mode = Node.PROCESS_MODE_PAUSABLE
	_world.add_child(_billboards)
	_billboards.setup(_pack.graph.edges.values(), _pack.ads, SESSION_SEED)
	var first: Vector3 = _billboards.sites[0]["transform"].origin if _billboards.count() > 0 else Vector3.ZERO
	print("billboards: %d boards from %d ads, tone %s, first at (%.0f, %.1f, %.0f)" % [_billboards.count(), _pack.ads.size(), ContentMode.current, first.x, first.y, first.z])
	var warning := _tone_warning()
	if warning != "":
		print("content: " + warning)


## Empty when the pack lists the active tone (or lists nothing).
func _tone_warning() -> String:
	var supported: Array = _pack.manifest.get("supported_modes", [])
	if supported.is_empty() or supported.has(ContentMode.current):
		return ""
	return "%s does not list tone %s; its content may be hidden" % [_pack.manifest.get("name", PACK_ID), ContentMode.mode_name()]


func _open_creator() -> void:
	_pause_menu.visible = false
	_creator.open(_player.profile if _player != null else {})


func _on_creator_closed(p: Dictionary) -> void:
	if _player != null:
		_player.apply_profile(p)
	Session.set_profile(p)
	_pause_menu.reopen()


func _host_game(port: int = Session.DEFAULT_PORT) -> void:
	if Session.is_online():
		return
	if Session.host(port) == OK:
		_set_mirror(false)
		_refresh_session_status()


func _join_game(address: String) -> void:
	if Session.is_online() or address == "":
		return
	var port := Session.DEFAULT_PORT
	var host := address
	if address.contains(":"):
		host = address.get_slice(":", 0)
		port = int(address.get_slice(":", 1))
	if Session.join(host, port) == OK:
		_pause_menu.set_status("joining %s:%d..." % [host, port])
		print("net: joining %s:%d" % [host, port])


func _on_joined(_info: Dictionary) -> void:
	_set_mirror(true)
	# Wait a moment for the other players' positions, then take the first slot along the road
	# from the host's spawn that nobody is standing in.
	await get_tree().create_timer(1.0).timeout
	var taken := _player_sync.remote_positions() if _player_sync != null else PackedVector3Array()
	var slot := 1
	for k in range(1, 12):
		var candidate := _spawn_transform.translated_local(Vector3(0.0, 0.0, 8.0 * k)).origin
		var clear := true
		for p in taken:
			if p.distance_to(candidate) < 6.0:
				clear = false
		if clear:
			slot = k
			break
	var t := _spawn_transform.translated_local(Vector3(0.0, 0.0, 8.0 * slot))
	_car.global_transform = t
	_car.linear_velocity = Vector3.ZERO
	_car.set_spawn(t)
	if not _player.is_driving():
		_player.global_position = t.origin - t.basis.x * ON_FOOT_OFFSET_M + Vector3.UP * 0.2
	_refresh_session_status()


## Clients mirror the host's traffic and people instead of simulating their own.
func _set_mirror(on: bool) -> void:
	if _traffic != null:
		_traffic.mirror = on
		if on:
			_traffic.agents.clear()
	if _peds != null:
		_peds.mirror = on
		if on:
			_peds.agents.clear()


func _refresh_session_status() -> void:
	var tone := "tone %s" % ContentMode.mode_name()
	var tone_warning := _tone_warning()
	if tone_warning != "":
		tone += "\n" + tone_warning
	if not Session.is_online():
		_pause_menu.set_status("offline, " + tone)
		return
	var names: Array = []
	for id in Session.peers:
		names.append(str(Session.peers[id].get("name", id)))
	var warn := "   (Deck host: 2 players is the comfortable limit)" if Session.is_host() and Session.peers.size() > 2 else ""
	var where := ""
	if Session.is_host():
		where = "\nfriends join at: %s  port %d" % [", ".join(Session.local_addresses()), Session.DEFAULT_PORT]
	_pause_menu.set_status("%s: %d/%d players: %s, %s%s%s" % [Session.role, Session.peers.size(), Session.max_players, ", ".join(names), tone, warn, where])


func _setup_pedestrians() -> void:
	var t0 := Time.get_ticks_msec()
	var walk := WalkGraph.build(_pack.graph.pedestrian)
	_peds = PedestrianManager.new()
	_peds.name = "Pedestrians"
	_peds.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_peds)
	_peds.setup(walk, _pack.graph, _traffic)
	if _peds_cap >= 0:
		_peds.max_agents = _peds_cap
	_peds.enabled = _peds_cap != 0
	print("pedestrians: %d walk paths in %d ms, cap %d" % [walk.paths.size(), Time.get_ticks_msec() - t0, _peds.max_agents])


func _setup_traffic() -> void:
	var t0 := Time.get_ticks_msec()
	var lane_graph := LaneGraph.build(_pack.graph, _pack.junctions)
	_traffic = TrafficManager.new()
	_traffic.name = "Traffic"
	_traffic.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_traffic)
	_traffic.setup(lane_graph, _pack.graph, _pack.junctions)
	if _traffic_cap >= 0:
		_traffic.max_agents = _traffic_cap
	_traffic.enabled = _traffic_cap != 0
	print("traffic: %d lane paths, %d signal heads, %d stop signs in %d ms, cap %d" % [lane_graph.paths.size(), _traffic.heads.count() if _traffic.heads != null else 0, _traffic.heads.sign_count() if _traffic.heads != null else 0, Time.get_ticks_msec() - t0, _traffic.max_agents])


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
		elif arg == "--creator":
			_open_creator_at_start = true
		elif arg.begins_with("--tone="):
			ContentMode.set_mode(arg.get_slice("=", 1), false)
		elif arg.begins_with("--camera="):
			for v in arg.get_slice("=", 1).split(","):
				_free_camera.append(float(v))
		elif arg == "--telemetry":
			_telemetry = true
		elif arg == "--bumps":
			_bumps = true
		elif arg.begins_with("--topdown"):
			_camera.mode = ChaseCamera.Mode.HIGH
			if arg.contains("="):
				_camera.height_override = float(arg.get_slice("=", 1))
		elif arg == "--graph":
			_graph_view.visible = true
		elif arg == "--map":
			_open_map_on_start = true
		elif arg == "--drive":
			_start_in_car = true
		elif arg.begins_with("--traffic="):
			_traffic_cap = int(arg.get_slice("=", 1))
		elif arg.begins_with("--peds="):
			_peds_cap = int(arg.get_slice("=", 1))
		elif arg == "--mute":
			_mute = true
		elif arg.begins_with("--time="):
			_start_hour = float(arg.get_slice("=", 1))
		elif arg.begins_with("--day-minutes="):
			_day_minutes = float(arg.get_slice("=", 1))
		elif arg.begins_with("--host"):
			_host_port = int(arg.get_slice("=", 1)) if arg.contains("=") else Session.DEFAULT_PORT
		elif arg.begins_with("--join="):
			_join_address = arg.get_slice("=", 1)
		elif arg.begins_with("--spawn="):
			var parts := arg.get_slice("=", 1).split(",")
			if parts.size() == 2:
				_spawn_override = Vector3(float(parts[0]), 0.0, float(parts[1]))


## Remembers which device the player last used so the hints match it; captures the mouse
## for looking around on foot on the desktop, releasing it for menus.
func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		if event is InputEventMouseMotion and not _keyboard:
			return  # a resting mouse jitters; a key or click switches
		_keyboard = true
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.3):
		_keyboard = false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and _player != null and not _player.is_driving() and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _hint(controller: String, keyboard: String) -> String:
	return keyboard if _keyboard else controller


func _process(delta: float) -> void:
	if _player != null and (get_tree().paused or _player.is_driving() or not _keyboard) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _car != null:
		var body: Node3D = Players.local_controlled_body()
		var anchors := PackedVector3Array([body.global_position])
		var obstacles: Array[Node3D] = [body]
		if Session.is_host() and _player_sync != null:
			anchors.append_array(_player_sync.remote_positions())
			for id in _player_sync.remotes:
				obstacles.append(_player_sync.remotes[id])
		if _streamer != null:
			_streamer.anchors = anchors
		if _traffic != null:
			_traffic.anchors = anchors
			_traffic.obstacles = obstacles
		if _peds != null:
			_peds.anchors = anchors
			_peds.obstacles = obstacles
			if _traffic != null:
				_traffic.obstacle_points = _peds.crossing_positions()
		if _traffic.lanes != null and _graph_view.visible != (_traffic._debug_mesh != null and _traffic._debug_mesh.visible):
			_traffic.set_debug_visible(_graph_view.visible)
	if _car != null and _player != null:
		_bench_elapsed_hud(delta)
		var body: Node3D = Players.local_controlled_body()
		var net := ""
		if Session.is_online():
			net = "  |  co-op %s %d/%d" % [Session.role, Session.peers.size(), Session.max_players]
		if _day_night != null:
			net = "  |  %s" % _day_night.clock_text() + net
			var amount := _day_night.night_factor()
			if _headlights == Headlights.ON:
				amount = 1.0
			elif _headlights == Headlights.OFF:
				amount = 0.0
			_car.set_headlights(amount)
			if _headlights != Headlights.AUTO:
				net += "  |  lights %s" % ("on" if _headlights == Headlights.ON else "off")
		if _player.is_driving():
			_hud.text = "%d km/h%s\nx %.0f  y %.1f  z %.0f     %s" % [
				int(_car.speed_kph()), net, body.global_position.x, body.global_position.y, body.global_position.z,
				_hint("RT accelerate, LT brake/reverse, RB handbrake, Y get out, D-pad down camera, D-pad up lights, Back map, Menu pause", "W accelerate, S brake/reverse, A D steer, Space handbrake, E get out, V camera, H lights, M map, Esc pause"),
			]
			_prompt.text = ""
		else:
			_hud.text = "on foot%s\nx %.0f  y %.1f  z %.0f     %s" % [
				net, body.global_position.x, body.global_position.y, body.global_position.z,
				_hint("left stick walk, L3 run, A jump, right stick look, Y get in, Back map, Menu pause", "WASD walk, Shift run, Space jump, click then mouse to look, E get in, M map, Esc pause"),
			]
			_prompt.text = _hint("Y  get in", "E  get in") if _player.nearest_vehicle() != null else ""
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
	if _fixed_cam != null and not _fixed_cam.current:
		_fixed_cam.current = true  # the player's cameras grab the viewport on enter/exit; the fixed view wins
	if Input.is_action_just_pressed("headlights_cycle") and _player != null and _player.is_driving():
		_headlights = (_headlights + 1) % 3
	if Input.is_action_just_pressed("camera_cycle") and _player != null and _player.is_driving():
		_camera.cycle_mode()
		_camera.look_at(_car.global_position, Vector3.UP)
	if _bench_seconds > 0.0:
		_bench_elapsed += delta
		if _bench_elapsed > BENCH_WARMUP_S:
			_bench_frames.append(delta * 1000.0)
			var rid := get_viewport().get_viewport_rid()
			_bench_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			_bench_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			_bench_physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
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
		var phys_sum := 0.0
		var phys_max := 0.0
		for v in _bench_physics:
			phys_sum += v
			phys_max = maxf(phys_max, v)
		var phys_mean := phys_sum / maxi(_bench_physics.size(), 1)
		print("benchmark: traffic agents %d, physics process mean %.2f ms max %.2f ms" % [_traffic.active_count(), phys_mean, phys_max])
	if _traffic != null:
		print("benchmark: traffic cost %s" % _traffic.profile_line())
	if _peds != null:
		print("benchmark: pedestrians %d, cost %s" % [_peds.active_count(), _peds.profile_line()])
	if _streamer != null:
		print("benchmark: chunks in scene %d, built %d, downgraded %d, freed %d, failed %d, first playable %d ms" % [_streamer.chunk_count(), _streamer.stats["built"], _streamer.stats["downgraded"], _streamer.stats["freed"], _streamer.stats["failed"], _first_playable_ms])
		print("benchmark: streamer cost add max %.1f ms (ema %.2f), shapes max %.1f ms (ema %.2f), frames over 8 ms %d" % [_streamer.profile["add_max_ms"], _streamer.profile["add_ema_ms"], _streamer.profile["shape_max_ms"], _streamer.profile["shape_ema_ms"], _streamer.profile["slow_frames"]])


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
