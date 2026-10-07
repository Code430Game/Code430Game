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
const HORN_STARTLE_M := 25.0  # pedestrians this close turn to look when the horn sounds

@onready var _world: Node3D = $World
@onready var _camera: ChaseCamera = $ChaseCamera
@onready var _hud: Label = $HUD/Label
@onready var _prompt: Label = $HUD/Prompt
@onready var _graph_view: RoadGraphDebugView = $GraphView
@onready var _minimap: Minimap = $HUD/Minimap
@onready var _overview: OverviewMap = $OverviewMap
@onready var _pause_menu: PauseMenu = $PauseMenu
@onready var _creator: CharacterCreator = $CharacterCreator
@onready var _report_form: ReportForm = $ReportForm
var _report_from_pause: bool = false  # where the report form returns to
var _billboards: Billboards = null
const SESSION_SEED := 430  # until sessions carry their own seed
var _map_renderer: MapRenderer
var _traffic: TrafficManager
var _traffic_cap: int = -1
var _peds: PedestrianManager
var _peds_cap: int = -1
var _parked: ParkedCars
var _parking_occupancy: float = -1.0  # --parking-occupancy=0..1: pin the share of full stalls (screenshots)
var _knockdown_every: float = 0.0  # --knockdown-every=S: benchmark knocks down the nearest pedestrian every S seconds
var _knockdown_timer: float = 0.0
var _knockdowns: int = 0
var _bench_falling: PackedFloat32Array = PackedFloat32Array()  # ragdolls simulating per frame after warm-up
var _player_sync: PlayerSync
var _world_sync: WorldSync
var _host_port: int = -1  # --host[=port]
var _join_address: String = ""  # --join=address[:port]
var _spawn_transform: Transform3D
var _keyboard: bool = false  # last input came from keyboard or mouse: show those hints
var _day_night: DayNight
var _vehicle_audio: VehicleAudio
var _reset_ring: HoldRing
var _foot_reset_s: float = 0.0  # seconds reset has been held on foot; -1 once it fired
var _shooter: Shooter
var _combat_effects: CombatEffects
var _wanted: Wanted
var _stars_label: Label
var _seen_badge: SeenBadge
var _police: PoliceManager
var _ambulances: AmbulanceManager
var _ambulance_log: bool = false  # --ambulance-log: print calls and ambulances each second
var _banner: Label
var _banner_shown: int = 0  # counts banners, so only the latest one's timer hides it
var _lit_car: VehicleBody3D  # the car whose headlights the lights setting drives: the one driven last
var _radio: Radio
var _radio_start: String = ""  # --radio=<station id|off>: tune to it at start
var _record_music: String = ""  # --record-music=<path.wav>: record the Music bus, saved when the benchmark ends
var _music_recorder: AudioEffectRecord
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
var _police_log: bool = false  # --police-log: print the chase each second
var _wanted_at_start: int = 0  # --wanted=N: start with N stars (screenshots, chases on demand)
var _weapon_at_start: int = 0  # --weapon=1|2: hold the melee weapon or the gun from the start (screenshots)
var _shots_at_start: int = 0  # --shoot=N: aim and fire N times once the world is up (screenshots)
var _fists_at_start: String = ""  # --fists=punch|kick: hold a punch or kick mid-move (screenshots)
var _officer_at_start: String = ""  # --officer=stagger|down|tagged: an officer in front, hit into that state (screenshots)
var _wheel_at_start: int = -2  # --wheel=N: open the weapon wheel pointing at entry N (-1: none) (screenshots)
var _menu_at_start: String = ""  # --menu=game|coop|controls|options|settings[,keyboard]: open the pause menu on that tab (screenshots)
var _report_at_start: String = ""  # --report: open the report form once loaded; --report-send: and save/send it
var _report_title: String = ""  # --report-title=...: the title for --report-send (tests of the relay)
var _report_tags: PackedStringArray = []  # --report-tags=stuck,police: quick tags picked on the opened form
var _junction_report := false  # --junction-report: print bulging, gapped and hull junctions with x, z once loaded
var _free_camera: PackedFloat64Array = PackedFloat64Array()  # --camera=px,py,pz,tx,ty,tz: fixed camera for screenshots
var _fixed_cam: Camera3D = null
var _bus_share_override: float = -1.0  # --bus-share=0..1: fraction of traffic spawned as buses (screenshots)
enum Headlights { AUTO, ON, OFF }
var _headlights: int = Headlights.AUTO  # D-pad right / H cycles auto (dusk to dawn), on, off
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
var _spawn_on_foot_at: Vector3 = Vector3.INF  # --spawn=x,y,z: the player starts on foot exactly here (a garage floor)
var _car_id: String = ""  # --car=<vehicle id>: start in this catalogue vehicle (default: the catalogue's)
var _road_label: String = ""
var _road_label_next: float = 0.0
var _open_map_on_start: bool = false
var _map_pick: String = ""  # --map-pick=kind[,n]: open that kind in the legend and pick place n


func _ready() -> void:
	# The testbed itself keeps running while the overview map pauses the game, so the
	# HUD, benchmark, and screenshot logic work with the map open. Children that must
	# freeze are set pausable explicitly.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	_camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	_graph_view.process_mode = Node.PROCESS_MODE_PAUSABLE
	_parse_args()
	_reset_ring = HoldRing.new()
	_reset_ring.name = "ResetRing"
	_reset_ring.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_reset_ring.position = Vector2(-20.0, -170.0)
	_reset_ring.text = "reset"
	$HUD.add_child(_reset_ring)
	_pause_menu.overview_map = _overview
	_pause_menu.quit_requested.connect(func() -> void: get_tree().quit())
	_pause_menu.character_requested.connect(_open_creator)
	_creator.profile_changed.connect(func(p: Dictionary) -> void: if _player != null: _player.apply_profile(p))
	_creator.closed.connect(_on_creator_closed)
	var report_config := ReportConfig.read()
	_report_form.store = ReportStore.new()
	_report_form.repo = report_config["repo"]
	_report_form.store.prune()
	# Reports go to the relay once one is configured; until then they are saved (and can be filed
	# in the browser on desktop).
	var relay := RelayClient.new()
	relay.name = "RelayClient"
	relay.store = _report_form.store
	relay.relay_url = report_config["relay_url"]
	add_child(relay)
	if relay.configured():
		_report_form.sender = relay
		relay.report_state_changed.connect(_report_form.on_report_state)
		relay.send_due()
	_pause_menu.report_requested.connect(func() -> void: _open_report(true))
	_report_form.closed.connect(_on_report_closed)
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
	VehicleCatalogue.merge_pack_dir(dir)  # a pack may add vehicles
	var t0 := Time.get_ticks_msec()
	_streamer = ChunkStreamer.new()
	_streamer.name = "Streamer"
	_streamer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_streamer)
	_streamer.setup(_pack, _world)
	print("testbed: streamer ready (%d chunks indexed, glb cache %s) in %d ms" % [_pack.chunk_coords().size(), _streamer.use_glb, Time.get_ticks_msec() - t0])
	if _junction_report:
		print(JunctionReport.format(JunctionReport.analyse(_pack)))
	_graph_view.set_graph(_pack.graph)
	_car = CAR_SCENE.instantiate()
	_car.set("vehicle_id", _car_id)
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
	_player.global_position = spawn.origin + spawn.basis.x * ON_FOOT_OFFSET_M + Vector3.UP * 0.2
	if _spawn_on_foot_at != Vector3.INF:
		_player.global_position = _spawn_on_foot_at
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
	_setup_day_night()  # before the parked cars, which fill their stalls for the clock's hour
	_setup_parked_cars()
	_setup_audio()
	_setup_combat()
	_setup_net()
	_setup_billboards()
	ContentMode.mode_changed.connect(func(_id: String) -> void: _refresh_session_status())
	if _open_creator_at_start:
		get_tree().create_timer(1.5).timeout.connect(_open_creator)
	if _wanted_at_start > 0 and _wanted != null:
		get_tree().create_timer(1.0).timeout.connect(func() -> void: _wanted.set_stars(_wanted_at_start))
	if _weapon_at_start > 0 and _shooter != null:
		get_tree().create_timer(1.2).timeout.connect(_demo_fire)
	if _wheel_at_start > -2 and _shooter != null:
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			_shooter.wheel.open_wheel()
			_shooter.wheel.select(_wheel_at_start))
	if _officer_at_start != "" and _police != null:
		get_tree().create_timer(1.5).timeout.connect(func() -> void: _police.demo_officer(_officer_at_start, _player))
	if _fists_at_start != "" and _shooter != null:
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if _shooter.held != null:
				_shooter.held.hold_move = _fists_at_start
				_shooter.held.hold_t = 0.45 if _fists_at_start == "punch" else 0.58)
	if _menu_at_start != "":
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_pause_menu.open()
			_pause_menu.showing_pad = not _menu_at_start.ends_with(",keyboard")
			var want := _menu_at_start.get_slice(",", 0).to_lower().replace("-", "")
			var index := 0
			for i in range(PauseMenu.TABS.size()):
				if PauseMenu.TABS[i].to_lower().replace("-", "") == want:
					index = i
			_pause_menu.show_tab(index))
	if _report_at_start != "":
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			_pause_menu.capture()
			_open_report(false)
			if _report_title != "":
				_report_form._title.text = _report_title
			for tag in _report_tags:
				_report_form.toggle_tag(tag)
			if _report_at_start == "send":
				print("report: saved %s" % _report_form.send()))
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
	if _vehicle_audio != null:
		_vehicle_audio.attach(car)  # the engine follows the player into whichever car they take
	if _radio != null:
		_radio.car_entered(car)  # tunes to the car's own station
	_camera.target = car
	_camera.global_position = car.global_position + car.global_basis.z * 7.5 + Vector3.UP * 3.0
	_camera.current = true
	_minimap.player = car
	_overview.player = car


func _on_take_vehicle_requested(traffic_body: Node3D) -> void:
	if _parked != null and traffic_body.has_meta("parked_key"):
		if Session.is_client():
			_world_sync.request_take_parked(str(traffic_body.get_meta("parked_key")))  # the host answers via _on_take_granted
			return
		var parked_car := _parked.take(traffic_body)
		if parked_car != null:
			_report_theft(parked_car.global_position)
			_player.enter_vehicle(parked_car)
		return
	if _traffic == null or not (traffic_body is TrafficCar):
		return
	if Session.is_client():
		_world_sync.request_take(traffic_body.global_position)  # the host owns the car; answer in _on_take_granted
		return
	var car := _traffic.take_car(traffic_body as TrafficCar)
	if car != null:
		_report_theft(car.global_position)
		_player.enter_vehicle(car)


## A car was taken at `at`: a theft, if the police see it.
func _report_theft(at: Vector3) -> void:
	if _wanted != null and _wanted.police_sees(at):
		_wanted.report("theft", at)


func _on_take_granted(t: Transform3D, color: Color, vehicle_id: String, station: String) -> void:
	var car: VehicleBody3D = TrafficManager.DRIVABLE_CAR_SCENE.instantiate()
	car.set("body_color", color)
	car.set("vehicle_id", vehicle_id)
	car.set("radio_station", station)  # the host's pick, so the car plays the same on every peer
	add_child(car)
	car.global_transform = t.translated_local(Vector3(0.0, 0.1, 0.0))
	car.set_spawn(car.global_transform)
	_report_theft(car.global_position)
	if not _player.is_driving():
		_player.enter_vehicle(car)


func _on_exited_vehicle(_car_left: VehicleBody3D) -> void:
	if _radio != null:
		_radio.car_exited()
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
	_day_night.register_emissive(VehicleMesh.light_material(), VehicleMesh.LIGHT_NIGHT_ENERGY)
	_day_night.register_emissive(VehicleMesh.tail_material(), VehicleMesh.LIGHT_NIGHT_ENERGY * 0.6)
	if _traffic != null and _traffic.tail_material != null:
		_day_night.register_shader(_traffic.tail_material)
	_day_night.register_shader(SignalHeads.head_material())
	var preset: Dictionary = Settings.presets.get(Settings.current_preset_name, {})
	_car.add_headlights(bool(preset.get("headlight_shadows", false)))


func _setup_audio() -> void:
	if _mute:
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	_vehicle_audio = VehicleAudio.new()
	_vehicle_audio.name = "VehicleAudio"
	_vehicle_audio.attach(_car)
	_radio = Radio.new()
	_radio.name = "Radio"
	add_child(_radio)
	_pause_menu.radio = _radio
	if _radio_start != "":
		_radio.select(_radio_start if _radio_start == Radio.OFF or _radio_start.contains(".") else "code430.base." + _radio_start)
	if _player != null and _player.is_driving():
		_radio.car_entered(_player.vehicle)
	if _record_music != "":
		_music_recorder = AudioEffectRecord.new()
		AudioServer.add_bus_effect(AudioServer.get_bus_index("Music"), _music_recorder)
		_music_recorder.set_recording_active(true)
	_ambience = AmbienceAudio.new()
	_ambience.name = "Ambience"
	_ambience.traffic = _traffic
	add_child(_ambience)


## --weapon / --shoot: holds a weapon, aims and fires a few times for screenshots.
func _demo_fire() -> void:
	_shooter.weapons.slot = _weapon_at_start
	_shooter.hold_aim = _shots_at_start > 0 and _weapon_at_start != 1  # melee swings without aiming
	for i in range(_shots_at_start):
		_player.aiming = true
		_shooter._cooldown = 0.0
		_shooter._reload_left = 0.0
		_shooter.pull_trigger()
		await get_tree().create_timer(0.25).timeout
		if i % 3 == 2:
			_player._yaw += 0.15  # spread the marks along the wall
	_player.aiming = true


## Weapons on foot (add-weapons-and-combat): the shooter, its marks and sounds, and the HUD
## line and reticle.
func _update_stars() -> void:
	var text := _wanted.stars_text()
	if ContentMode.flag("lethal_weapons") and _player.health < float(_wanted.config.get("player_health", 100.0)):
		text += "   ♥ %d" % int(ceil(_player.health))
	_stars_label.text = text


## Police fire (lethal modes): health down; at zero the player is wasted.
func _hurt(damage: float) -> void:
	if not ContentMode.flag("lethal_weapons"):
		return
	_player.health -= damage
	_update_stars()
	if _player.health <= 0.0:
		_caught("wasted")


## Busted or wasted: a banner, the wanted level and the police cleared, health and weapons
## refilled, and the player back at the start on foot.
func _caught(how: String) -> void:
	# Taken to the nearest police station when busted, the nearest hospital when wasted
	# (add-emergency-services); the start when the pack has none.
	var place := Services.nearest(_pack.services, "hospital" if how == "wasted" else "police", _player.global_position)
	var arrive_at := Services.arrival(place, _pack.graph) if place != null else _pack.spawn_transform().origin
	var text := "WASTED" if how == "wasted" else "BUSTED"
	if not ContentMode.flag("lethal_weapons"):
		text = "CAUGHT! Fined for mischief"
	if place != null and place.name != "":
		text += "\n" + place.name
	_show_banner(text)
	_police.reset()
	if _ambulances != null:
		_ambulances.reset()
	_wanted.clear()
	if _player.is_driving():
		_player.try_exit_vehicle()
	_place_player(arrive_at)
	_player.stuck_s = 0.0
	_player.health = float(_wanted.config.get("player_health", 100.0))
	_shooter.reset()
	_shooter.weapons.refill()
	_update_stars()


## Puts the player on foot 1 m above `at`, building the ground there first: after a jump across
## the map the chunk's collision may not have streamed in yet, and the player fell through it.
func _place_player(at: Vector3) -> void:
	_streamer.build_now(at)
	_player.global_position = at + Vector3.UP * 1.0
	_player.velocity = Vector3.ZERO


## On foot, holding reset (R3 / R, like a stuck car) for the hold time takes the player back to
## the start, so a player stuck somewhere needn't restart the game. Returns the hold's progress
## (0..1) for the HUD ring.
func _step_foot_reset(held: bool, delta: float) -> float:
	if not held:
		_foot_reset_s = 0.0
		return 0.0
	if _foot_reset_s < 0.0:
		return 0.0  # already reset on this hold
	_foot_reset_s += delta
	if _foot_reset_s < Controls.hold_s():
		return _foot_reset_s / Controls.hold_s()
	_foot_reset_s = -1.0
	_place_player(_pack.spawn_transform().origin)
	return 0.0


## Shows `text` on the banner for `banner_s`; a newer banner restarts the time.
func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_shown += 1
	var shown := _banner_shown
	get_tree().create_timer(float(_wanted.config.get("banner_s", 3.0))).timeout.connect(func() -> void:
		if shown == _banner_shown:
			_banner.visible = false)


func _setup_combat() -> void:
	if _player == null:
		return
	_combat_effects = CombatEffects.new()
	_combat_effects.name = "CombatEffects"
	_world.add_child(_combat_effects)
	var label := Label.new()
	label.name = "Weapon"
	label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	label.position = Vector2(-320.0, 16.0)
	label.size = Vector2(300.0, 30.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	$HUD.add_child(label)
	var reticle := ColorRect.new()
	reticle.name = "Reticle"
	reticle.color = Color(1, 1, 1, 0.9)
	reticle.size = Vector2(6, 6)
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.position = Vector2(-3, -3)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.visible = false
	$HUD.add_child(reticle)
	_shooter = Shooter.new()
	_shooter.name = "Shooter"
	_shooter.player = _player
	_shooter.peds = _peds
	_shooter.effects = _combat_effects
	_shooter.hud = label
	_shooter.reticle = reticle
	# The weapon wheel on its own layer after the pause menu, so B / Esc close it first; the
	# idle tile under the wanted stars (add-weapon-selector).
	var wheel_layer := CanvasLayer.new()
	wheel_layer.name = "WheelLayer"
	wheel_layer.layer = ($HUD as CanvasLayer).layer
	add_child(wheel_layer)
	_shooter.wheel = WeaponWheel.new()
	_shooter.wheel.name = "WeaponWheel"
	wheel_layer.add_child(_shooter.wheel)
	_shooter.tile = WeaponTile.new()
	_shooter.tile.name = "WeaponTile"
	_shooter.tile.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_shooter.tile.position = Vector2(-20.0 - _shooter.tile.size.x, 86.0)
	$HUD.add_child(_shooter.tile)
	add_child(_shooter)
	_setup_wanted()


## The wanted level (add-police): crimes from weapons, car hits and car theft; stars on the HUD.
func _setup_wanted() -> void:
	_wanted = Wanted.new()
	_wanted.name = "Wanted"
	_wanted.peds = _peds
	add_child(_wanted)
	_stars_label = Label.new()
	_stars_label.name = "Stars"
	_stars_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stars_label.position = Vector2(-320.0, 44.0)
	_stars_label.size = Vector2(300.0, 36.0)
	_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stars_label.add_theme_font_size_override("font_size", 28)
	_stars_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_stars_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	$HUD.add_child(_stars_label)
	# Whether the police can see the player, beside the weapon tile under the stars
	# (update-police-pursuit).
	_seen_badge = SeenBadge.new()
	_seen_badge.name = "SeenBadge"
	_seen_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_seen_badge.position = Vector2(-20.0 - 40.0 - 10.0 - _seen_badge.size.x, 84.0)
	_seen_badge.visible = false
	$HUD.add_child(_seen_badge)
	_wanted.stars_changed.connect(func(_n: int) -> void: _update_stars())
	_police = PoliceManager.new()
	_police.name = "Police"
	_police.process_mode = Node.PROCESS_MODE_PAUSABLE
	_police.wanted = _wanted
	_police.graph = _pack.graph
	_police.player = _player
	_police.holder = _world
	_police.stations = _pack.services.filter(func(p: Services.Place) -> bool: return p.kind == "police")
	_police.helipads = _pack.services.filter(func(p: Services.Place) -> bool: return p.kind == "helipad")
	_police.log_chase = _police_log
	_police.canopy = CanopyCover.from_chunks(_pack.vegetation_chunks, _wanted.config.get("canopy", {}))
	add_child(_police)
	_shooter.police = _police
	_police.busted.connect(func() -> void: _caught("busted"))
	_police.net_hit.connect(func(seconds: float) -> void: _player.stuck_s = maxf(_player.stuck_s, seconds))
	_police.shot_at.connect(_hurt)
	_police.taken.connect(func(car: VehicleBody3D) -> void: _wanted.report("theft", car.global_position))
	_banner = Label.new()
	_banner.name = "Banner"
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.position = Vector2(-400.0, -120.0)
	_banner.size = Vector2(800.0, 80.0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 52)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_banner.add_theme_color_override("font_shadow_color", Color.BLACK)
	_banner.visible = false
	$HUD.add_child(_banner)
	_shooter.fired.connect(func(w: Dictionary) -> void:
		if str(w.get("mechanic", "")) != "melee" and bool(w.get("lethal", false)):
			_wanted.report("gunfire", _player.global_position))
	_shooter.hit_person.connect(func(a: Pedestrian, _w: Dictionary, downed: bool) -> void:
		_wanted.report("assault_down" if downed else "assault", a.position()))
	if _peds != null:
		_peds.struck_by_vehicle.connect(func(a: Pedestrian, vehicle: Node3D) -> void:
			if vehicle == _driven_car() and _player.is_driving():
				_wanted.report("assault_down", a.position()))
		_ambulances = AmbulanceManager.new()
		_ambulances.name = "Ambulances"
		_ambulances.process_mode = Node.PROCESS_MODE_PAUSABLE
		_ambulances.peds = _peds
		_ambulances.graph = _pack.graph
		_ambulances.holder = _world
		_ambulances.player = _player
		_ambulances.bases = _pack.services.filter(func(p: Services.Place) -> bool: return p.kind in ["ambulance", "hospital"])
		_ambulances.log_runs = _ambulance_log
		add_child(_ambulances)
		_ambulances.taken.connect(func(car: VehicleBody3D) -> void: _wanted.report("theft", car.global_position))
		_ambulances.rammed.connect(func(by: Node3D, at: Vector3) -> void:
			if by == _driven_car() and _player.is_driving():
				_wanted.report("assault", at))


func _setup_net() -> void:
	Session.local_manifest = _pack.manifest_summary()
	_player_sync = PlayerSync.new()
	_player_sync.name = "PlayerSync"
	_player_sync.player = _player
	_player_sync.remote_parent = _world
	_player_sync.remote_horn.connect(func(at: Vector3) -> void: if _peds != null and Session.is_host(): _peds.startle(at, HORN_STARTLE_M))
	add_child(_player_sync)
	_world_sync = WorldSync.new()
	_world_sync.name = "WorldSync"
	_world_sync.traffic = _traffic
	_world_sync.peds = _peds
	_world_sync.parked = _parked
	if _parked != null:
		_parked.stall_taken.connect(_world_sync.announce_stall_taken)
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
	_billboards.setup(_pack.graph.edges.values(), _pack.ads, SESSION_SEED, Billboards.obstacles_from_pack(_pack))
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


## F8 opens the report form straight from play (controllers hold Menu instead).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("report_open") and not get_tree().paused and _pack != null:
		_pause_menu.capture()
		_open_report(false)
		get_viewport().set_input_as_handled()


## Opens "Report a problem" with the frame and frame times the pause menu captured, the place,
## the loaded pack and the log tail.
func _open_report(from_pause: bool) -> void:
	_report_from_pause = from_pause
	_pause_menu.visible = false
	var body: Node3D = Players.local_controlled_body()
	var driving := _player != null and _player.is_driving()
	var clock := _day_night.clock_text() if _day_night != null else ""
	var place := Diagnostics.place_for(_pack.graph if _pack != null else null, body, driving, clock)
	var packs := []
	if _pack != null:
		var summary := _pack.manifest_summary()
		packs.append({"id": summary["id"], "version": summary["version"]})
	var redactor := Diagnostics.local_redactor()
	var diag := Diagnostics.collect(place, packs, _pause_menu.captured_frame_stats, redactor)
	_report_form.open(_pause_menu.captured_frame, diag, Diagnostics.log_tail(redactor))


func _on_report_closed() -> void:
	if _report_from_pause:
		_pause_menu.reopen()
	else:
		get_tree().paused = false


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
		_player.global_position = t.origin + t.basis.x * ON_FOOT_OFFSET_M + Vector3.UP * 0.2
	_refresh_session_status()


## Clients mirror the host's traffic and people instead of simulating their own.
func _set_mirror(on: bool) -> void:
	if _traffic != null:
		_traffic.mirror = on
		if on:
			_traffic.clear_agents()
	if _peds != null:
		_peds.mirror = on
		if on:
			_peds.clear_agents()


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


func _setup_parked_cars() -> void:
	_parked = ParkedCars.new()
	_parked.name = "ParkedCars"
	_parked.process_mode = Node.PROCESS_MODE_PAUSABLE
	_parked.occupancy_override = _parking_occupancy
	if _day_night != null:
		_parked.hour = _day_night.hour
	add_child(_parked)
	_parked.setup(_pack.parking_lots)
	print("parking: %d lots, %d parked cars at %.0f:00" % [_pack.parking_lots.size(), _parked.cars.size(), _parked.hour])


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
	if _bus_share_override >= 0.0:
		# The bus's catalogue weight that gives this share of an arterial's traffic.
		var others := 0.0
		for id in VehicleCatalogue.ids():
			if id != "bus":
				others += VehicleCatalogue.spawn_weight(VehicleCatalogue.entry(id), "primary", 12.0)
		var share := clampf(_bus_share_override, 0.0, 0.95)
		(VehicleCatalogue.entry("bus")["spawn"] as Dictionary)["weight"] = others * share / (1.0 - share)
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
	_minimap.garages = _pack.garages
	_overview.renderer = _map_renderer
	_overview.graph = _pack.graph
	_overview.player = Players.local_controlled_body()
	var places: Array = _pack.services.duplicate()
	places.append_array(Services.garage_places(_pack.parking_lots, _pack.graph, PlaceIcons.num("garage_street_m", 120.0)))
	_overview.places = places
	_minimap.places = places
	var t0 := Time.get_ticks_msec()
	await _map_renderer.render(self, _pack.graph, _pack.water_polygons, _pack.buildings, _pack.parking_lots, _pack.green_areas)
	print("map texture %s rendered in %d ms" % [_map_renderer.size_px, Time.get_ticks_msec() - t0])
	if _open_map_on_start or _map_pick != "":
		_overview.open()
	if _map_pick != "":
		var kinds := _overview.legend.kinds_present()
		_overview.legend.select(maxi(kinds.find(_map_pick.get_slice(",", 0)), 0))
		_overview.legend.accept()
		if _map_pick.contains(","):
			_overview.legend.select(int(_map_pick.get_slice(",", 1)))
			_overview.legend.accept()


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
	var lane_w := e.carriageway_m() / maxf(lanes_total, 1)
	var divider := e.carriageway_offset() + e.carriageway_m() * 0.5 - e.lanes_forward * lane_w
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
		elif arg == "--police-log":
			_police_log = true
		elif arg == "--ambulance-log":
			_ambulance_log = true
		elif arg.begins_with("--wanted="):
			_wanted_at_start = int(arg.get_slice("=", 1))
		elif arg.begins_with("--weapon="):
			_weapon_at_start = int(arg.get_slice("=", 1))
		elif arg.begins_with("--shoot="):
			_shots_at_start = int(arg.get_slice("=", 1))
		elif arg.begins_with("--fists="):
			_fists_at_start = arg.get_slice("=", 1)
		elif arg.begins_with("--officer="):
			_officer_at_start = arg.get_slice("=", 1)
		elif arg.begins_with("--wheel="):
			_wheel_at_start = int(arg.get_slice("=", 1))
		elif arg.begins_with("--menu="):
			_menu_at_start = arg.get_slice("=", 1)
		elif arg.begins_with("--record-music="):
			_record_music = arg.get_slice("=", 1)
		elif arg.begins_with("--radio="):
			_radio_start = arg.get_slice("=", 1)
		elif arg.begins_with("--report-tags="):
			_report_tags = arg.get_slice("=", 1).split(",", false)
		elif arg.begins_with("--report-title="):
			_report_title = arg.get_slice("=", 1)
		elif arg == "--report" or arg == "--report-send":
			_report_at_start = "send" if arg == "--report-send" else "open"
		elif arg.begins_with("--tone="):
			ContentMode.set_mode(arg.get_slice("=", 1), false)
		elif arg.begins_with("--bus-share="):
			_bus_share_override = float(arg.get_slice("=", 1))
		elif arg.begins_with("--camera="):
			for v in arg.get_slice("=", 1).split(","):
				_free_camera.append(float(v))
		elif arg == "--telemetry":
			_telemetry = true
		elif arg == "--junction-report":
			_junction_report = true
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
		elif arg.begins_with("--map-pick="):
			_map_pick = arg.get_slice("=", 1)
		elif arg == "--drive":
			_start_in_car = true
		elif arg.begins_with("--traffic="):
			_traffic_cap = int(arg.get_slice("=", 1))
		elif arg.begins_with("--parking-occupancy="):
			_parking_occupancy = float(arg.get_slice("=", 1))
		elif arg.begins_with("--car="):
			_car_id = arg.get_slice("=", 1)
		elif arg.begins_with("--peds="):
			_peds_cap = int(arg.get_slice("=", 1))
		elif arg.begins_with("--knockdown-every="):
			_knockdown_every = float(arg.get_slice("=", 1))
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
			elif parts.size() == 3:
				_spawn_override = Vector3(float(parts[0]), 0.0, float(parts[2]))
				_spawn_on_foot_at = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


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


## The HUD's one-line pointer to the full list (the pause menu's Controls tab), which used to be
## the whole layout and ran off the screen.
## The car the player is in, or the one they last drove (the start car until they take another).
## The headlights, the HUD's speed, the reset ring and the horn follow it; a taken car used to
## leave them all on the start car.
func _driven_car() -> VehicleBody3D:
	if _player != null and _player.is_driving() and _player.vehicle != null:
		return _player.vehicle
	return _lit_car if is_instance_valid(_lit_car) else _car


## Moves the headlights to the car being driven (adding them the first time), switches off the
## one left behind, and sets their brightness.
func _light_driven_car(amount: float) -> void:
	var car := _driven_car()
	if car != _lit_car:
		if is_instance_valid(_lit_car) and _lit_car.has_method("set_headlights"):
			_lit_car.set_headlights(0.0)
		if car.has_method("add_headlights") and (car.get("_headlights") as Array).is_empty():
			var preset: Dictionary = Settings.presets.get(Settings.current_preset_name, {})
			car.add_headlights(bool(preset.get("headlight_shadows", false)))
		_lit_car = car
	if car.has_method("set_headlights"):
		car.set_headlights(amount)


func _controls_hint() -> String:
	return _hint("Menu: pause, controls (LB / RB tabs)", "Esc: pause, controls (Q / E tabs)")


## True while a menu covers play (pause menu, full map, character creator, report form): the
## HUD (minimap, position line, badges) steps back for it (update-menu-design).
func menu_open() -> bool:
	return _pause_menu.visible or _overview.visible or _creator.visible or _report_form.visible


func _process(delta: float) -> void:
	if _player != null and (get_tree().paused or _player.is_driving() or not _keyboard) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	($HUD as CanvasLayer).visible = not menu_open()
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
			if _day_night != null:
				_traffic.hour = _day_night.hour
			if _ambulances != null:
				obstacles.append_array(_ambulances.bodies())  # traffic stops for them
			_traffic.obstacles = obstacles
		if _peds != null:
			_peds.anchors = anchors
			_peds.obstacles = obstacles
			_peds.emergency = _ambulances.calling_bodies() if _ambulances != null else ([] as Array[Node3D])
			if _traffic != null:
				_traffic.obstacle_points = _peds.crossing_positions()
			if _knockdown_every > 0.0 and _bench_elapsed > BENCH_WARMUP_S and not anchors.is_empty():
				_knockdown_timer -= delta
				if _knockdown_timer <= 0.0:
					_knockdown_timer = _knockdown_every
					var push := Vector3(randf_range(-1.0, 1.0), 0.15, randf_range(-1.0, 1.0)).normalized() * 900.0
					if _peds.knock_down_nearest(anchors[0], 60.0, push):
						_knockdowns += 1
				_bench_falling.append(_peds.falling_count())
		if _parked != null:
			_parked.anchors = anchors
			if _day_night != null:
				_parked.hour = _day_night.hour
		if _traffic.lanes != null and _graph_view.visible != (_traffic._debug_mesh != null and _traffic._debug_mesh.visible):
			_traffic.set_debug_visible(_graph_view.visible)
	_prompt.visible = not get_tree().paused  # under the pause menu it only showed through the dim
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
			_light_driven_car(amount)
			if _headlights != Headlights.AUTO:
				net += "  |  lights %s" % ("on" if _headlights == Headlights.ON else "off")
		if _player.is_driving():
			_hud.text = "%d km/h%s\nx %.0f  y %.1f  z %.0f     %s" % [
				int(_driven_car().speed_kph()), net, body.global_position.x, body.global_position.y, body.global_position.z,
				_controls_hint(),
			]
			_prompt.text = ""
		else:
			_hud.text = "on foot%s\nx %.0f  y %.1f  z %.0f     %s" % [
				net, body.global_position.x, body.global_position.y, body.global_position.z,
				_controls_hint(),
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
	# This node runs while paused so menus work; D-pad up and down navigate those menus (pause,
	# map, character creator), so the driving hotkeys on the same buttons only fire in play.
	var in_play := not get_tree().paused
	if in_play and Input.is_action_just_pressed("headlights_cycle") and _player != null and _player.is_driving():
		_headlights = (_headlights + 1) % 3
	var driving := _player != null and _player.is_driving()
	_camera.look_behind = in_play and driving and Input.is_action_pressed("look_behind")
	var on_foot := in_play and _player != null and not driving
	_reset_ring.progress = _driven_car().reset_progress() if driving else _step_foot_reset(on_foot and Input.is_action_pressed("reset_vehicle"), delta)
	if _wanted != null:
		_wanted.target = Players.local_controlled_body()
	if _police != null and _day_night != null:
		_police.night = _day_night.night_factor()
	if _minimap != null:
		var blips: Array = []
		if _ambulances != null:
			for at in _ambulances.positions():
				blips.append({"at": at, "color": Color(0.9, 0.15, 0.2)})
		if _police != null:
			for m: Dictionary in _police.markers():
				blips.append({"at": m["at"], "shape": "helicopter" if m["kind"] == "helicopter" else "dot", "flash": m["kind"] != "officer", "seen": m["sees"], "searching": m["searching"]})
		_minimap.blips = blips
	if _seen_badge != null and _wanted != null:
		_seen_badge.show_wanted(_wanted.stars, _wanted.helicopter_sees, _wanted.ground_sees, _wanted.hidden_progress())
	if in_play and driving and Input.is_action_just_pressed("horn") and _peds != null:
		_peds.startle(_driven_car().global_position, HORN_STARTLE_M)
	if in_play and Input.is_action_just_pressed("camera_cycle") and _player != null and _player.is_driving():
		_camera.cycle_mode()
		_camera.look_at(_driven_car().global_position, Vector3.UP)
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
			if _music_recorder != null:
				_music_recorder.set_recording_active(false)
				var rec := _music_recorder.get_recording()
				if rec != null:
					rec.save_to_wav(_record_music)
					print("music recording: %s (%.1f s)" % [_record_music, rec.get_length()])
			if _screenshot_path != "":
				await RenderingServer.frame_post_draw
				var err := get_viewport().get_texture().get_image().save_png(_screenshot_path)
				print("screenshot: %s (%s)" % [_screenshot_path, error_string(err)])
			get_tree().quit()


func _print_benchmark() -> void:
	if _radio != null:
		print("benchmark: " + _radio.describe())
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
		if _knockdown_every > 0.0:
			var falling := 0.0
			for f in _bench_falling:
				falling += f
			print("benchmark: knockdowns %d, ragdolls falling on average %.2f per frame" % [_knockdowns, falling / maxf(_bench_falling.size(), 1.0)])
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
