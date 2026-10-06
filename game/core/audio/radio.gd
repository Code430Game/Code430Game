class_name Radio
extends Node
## The car radio: four stations from `radio/radio.v0.json` plus Off, cycled with `radio_cycle`
## (D-pad left, Q) while the local player drives.
##
## Each station is one loop from `radio/music.v0.json`. Loops are never synthesised per frame: the
## first time a station is needed its loop renders on a WorkerThreadPool task into a looping
## AudioStreamWAV (about a second on a Mac), the station being played first and the others one
## at a time after it, and each render is cached under user://radio_cache/ keyed by the track's
## data, so later sessions load it at once. The station and the Music volume are remembered in
## settings.cfg. Getting in resumes the station where it paused; getting out pauses it.
##
## Each drivable car keeps its own station in its `radio_station` field: getting in tunes to the
## car's station, and changing station writes it back. A car with none yet (the player's own) takes
## the player's last choice; taken and emergency cars are handed one by `pick_for_car`.

signal tuned(name: String, tagline: String)

const STATIONS_PATH := "res://core/audio/radio/radio.v0.json"
const MUSIC_PATH := "res://core/audio/radio/music.v0.json"
const SECTION := "radio"
const KEY_STATION := "station"
const KEY_VOLUME := "music_volume_db"
const OFF := "off"
## The talk station emergency vehicles have on, when they have anything on.
const CHATTER := "code430.base.chatter"
## How often a taken car's radio is off.
const OFF_CHANCE := 0.2
const TOAST_S := 3.0
const CACHE_DIR := "user://radio_cache"
## Bump when the synth's output changes, so old cached loops are not reused.
const RENDER_VERSION := "2"
## Rendered before the loop and thrown away, so envelopes, held notes and the echo at the start of
## the kept pass are what a real repeat hands it (the dungeon's drone holds a whole bar).
const WARMUP_S := 4.0

var settings_path: String = Settings.DEFAULT_SETTINGS_PATH
var cache_dir: String = CACHE_DIR
var stations: Array = []  # station dictionaries from radio.v0.json, in cycle order
var tracks: Dictionary = {}  # track id -> track dictionary
var station_id: String = ""  # current station id, or OFF
var chosen_id: String = ""  # the player's last choice (saved); a car with no station yet takes it
var car: Node  # the car being driven, whose `radio_station` follows the dial
var driving: bool = false
var music_volume_db: float = -4.0
var _streams: Dictionary = {}  # track id -> AudioStreamWAV, once rendered
var _queue: Array = []  # track ids waiting to render, most urgent first
var _task: int = -1  # the WorkerThreadPool task rendering `_task_track`
var _task_track: String = ""
var _positions: Dictionary = {}  # track id -> seconds, where it paused
var _render_started: Dictionary = {}  # track id -> msec, for the log
var _player: AudioStreamPlayer
var _toast: Label
var _toast_left: float = 0.0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	add_child(_player)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-200, 40)
	_toast.size = Vector2(400, 60)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	layer.add_child(_toast)
	load_data()
	load_saved()
	_apply_volume()


func _exit_tree() -> void:
	_queue.clear()
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Reads the stations and tracks.
func load_data(stations_path: String = STATIONS_PATH, music_path: String = MUSIC_PATH) -> void:
	var st: Variant = JSON.parse_string(FileAccess.get_file_as_string(stations_path))
	var mu: Variant = JSON.parse_string(FileAccess.get_file_as_string(music_path))
	stations = (st as Dictionary).get("stations", []) if st is Dictionary else []
	tracks = {}
	if mu is Dictionary:
		for t in (mu as Dictionary).get("tracks", []):
			tracks[t["id"]] = t
	if station_id == "" and not stations.is_empty():
		station_id = stations[0]["id"]
	if chosen_id == "":
		chosen_id = station_id


## The cycle: every station id, then Off.
func cycle_ids() -> Array:
	var ids := []
	for s in stations:
		ids.append(s["id"])
	ids.append(OFF)
	return ids


## The station's variant for the active tone mode: {"name", "tagline", "track"}.
func variant(id: String) -> Dictionary:
	for s in stations:
		if s["id"] == id:
			return ContentMode.pick_variant(s)
	return {}


## Moves `delta` along the cycle, plays the new station if driving, saves the choice.
func cycle(delta: int = 1) -> void:
	var ids := cycle_ids()
	var i := ids.find(station_id)
	select(ids[posmod(i + delta, ids.size())])


## Tunes to a station id (or OFF), saves it as the player's choice, writes it to the car being
## driven, and plays it if driving.
func select(id: String) -> void:
	if id != OFF and variant(id).is_empty():
		return
	_pause_current()
	station_id = id
	chosen_id = id
	if car != null and is_instance_valid(car) and "radio_station" in car:
		car.set("radio_station", id)
	save()
	if id == OFF:
		_show_toast("Radio off", "")
	else:
		var v := variant(id)
		_show_toast(str(v.get("name", "")), str(v.get("tagline", "")))
	if driving:
		_play_current()


## The local player got into a car: tunes to its station, or gives it the player's choice when it
## has none (or one that no longer exists).
func car_entered(entered: Node = null) -> void:
	driving = true
	car = entered
	if car != null and "radio_station" in car:
		var own := str(car.get("radio_station"))
		if own != OFF and variant(own).is_empty():
			own = chosen_id
			car.set("radio_station", own)
		if own != station_id:
			_pause_current()
			station_id = own
	if station_id != OFF:
		var v := variant(station_id)
		_show_toast(str(v.get("name", "")), str(v.get("tagline", "")))
	_play_current()
	_prerender_all()


## The local player got out.
func car_exited() -> void:
	driving = false
	car = null
	_pause_current()


## A station for a car the player did not tune: a taken traffic or parked car plays a random station
## (sometimes off), an emergency vehicle Chatter AM or off. `car_seed` names the car, so the same car
## always gets the same answer (and every co-op peer the one the host picked).
static func pick_for_car(car_seed: int, emergency: bool = false) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = car_seed
	if emergency:
		return CHATTER if rng.randf() < 0.5 else OFF
	var ids := station_ids()
	if ids.is_empty() or rng.randf() < OFF_CHANCE:
		return OFF
	return ids[rng.randi() % ids.size()]


static var _station_ids: Array = []


## The station ids in radio.v0.json (no Off), read once.
static func station_ids() -> Array:
	if _station_ids.is_empty():
		var st: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATIONS_PATH))
		if st is Dictionary:
			for s in (st as Dictionary).get("stations", []):
				_station_ids.append(str(s["id"]))
	return _station_ids


## True while a station's loop is audible.
func is_playing() -> bool:
	return _player.playing


## The rendered loop for a track id, or null until its render finishes.
func stream_for(track_id: String) -> AudioStreamWAV:
	return _streams.get(track_id)


## One line for the benchmark summary: station, playing, loops rendered and under way.
func describe() -> String:
	return "radio: %s, driving %s, playing %s, rendered %d, rendering %d, bus %s %.1f dB" % [
		station_id, driving, _player.playing, _streams.size(), _queue.size() + (1 if _task != -1 else 0), _player.bus,
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index(_player.bus))]


## True while any loop is still rendering or waiting to.
func rendering() -> bool:
	return _task != -1 or not _queue.is_empty()


## Renders one loop to a looping 16-bit mono sample, warming up over the end of the loop first so
## the kept pass starts from the state a real repeat would (no click at the wrap).
static func render_loop(track: Dictionary) -> AudioStreamWAV:
	var song := ChipSong.from_dict(track)
	var n := song.loop_samples()
	var warm := mini(int(WARMUP_S * song.mix_rate), n)
	song.seek(n - warm)
	song.render(warm)
	var buf := song.render(n)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in range(n):
		pcm.encode_s16(i * 2, int(clampf(buf[i].x, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(song.mix_rate)
	wav.stereo = false
	wav.data = pcm
	_set_loop(wav, n)
	return wav


static func _set_loop(wav: AudioStreamWAV, n: int) -> void:
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n


## Where a track's rendered loop is cached: its id plus a hash of its data and the synth version.
static func cache_path(track: Dictionary, dir: String = CACHE_DIR) -> String:
	return dir.path_join("%s_%08x.wav" % [track.get("id", "track"), hash(JSON.stringify(track, "", true) + RENDER_VERSION) & 0xFFFFFFFF])


## The cached loop for a track, or null when there is none (or it cannot be read).
static func load_cached(track: Dictionary, dir: String = CACHE_DIR) -> AudioStreamWAV:
	var path := cache_path(track, dir)
	if not FileAccess.file_exists(path):
		return null
	var wav := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	if wav == null:
		return null
	_set_loop(wav, wav.data.size() / 2)
	return wav


## Queues a track's loop for rendering (urgent: ahead of the others). No-op when it is ready.
func request_render(track_id: String, urgent: bool = true) -> void:
	if _streams.has(track_id) or _task_track == track_id or not tracks.has(track_id):
		return
	_queue.erase(track_id)
	if urgent:
		_queue.push_front(track_id)
	else:
		_queue.push_back(track_id)
	_start_next()


func _start_next() -> void:
	if _task != -1 or _queue.is_empty():
		return
	var track_id: String = _queue.pop_front()
	var track: Dictionary = tracks[track_id]
	_task_track = track_id
	_render_started[track_id] = Time.get_ticks_msec()
	# The task touches only its own track and the cache file, then hands the stream back.
	var dir := cache_dir
	_task = WorkerThreadPool.add_task(func() -> void:
		var wav := Radio.load_cached(track, dir)
		var from_cache := wav != null
		if wav == null:
			wav = Radio.render_loop(track)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
			wav.save_to_wav(ProjectSettings.globalize_path(Radio.cache_path(track, dir)))
		_finish_render.call_deferred(track_id, wav, from_cache), true, "radio %s" % track_id)


func _finish_render(track_id: String, wav: AudioStreamWAV, from_cache: bool) -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_task_track = ""
	_streams[track_id] = wav
	print("radio: %s %s in %d ms" % [track_id, "loaded from cache" if from_cache else "rendered", Time.get_ticks_msec() - int(_render_started.get(track_id, 0))])
	if driving and station_id != OFF and str(variant(station_id).get("track", "")) == track_id:
		_play_current()
	_start_next()


func _prerender_all() -> void:
	# Headless runs (tests, CI) play nothing; render only what is asked for there.
	if DisplayServer.get_name() == "headless":
		return
	for s in stations:
		request_render(str(ContentMode.pick_variant(s).get("track", "")), false)


func _play_current() -> void:
	if not driving or station_id == OFF:
		_player.stop()
		return
	var track_id := str(variant(station_id).get("track", ""))
	var wav := stream_for(track_id)
	if wav == null:
		request_render(track_id)  # plays when it lands
		return
	if _player.stream != wav:
		_player.stream = wav
	_player.play(float(_positions.get(track_id, 0.0)))


func _pause_current() -> void:
	if _player.playing and _player.stream != null:
		for id in _streams:
			if _streams[id] == _player.stream:
				_positions[id] = _player.get_playback_position()
	_player.stop()


func _show_toast(title: String, tagline: String) -> void:
	_toast.text = title if tagline == "" else "%s\n%s" % [title, tagline]
	_toast.visible = true
	_toast_left = TOAST_S


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if driving and not get_tree().paused and event.is_action_pressed("radio_cycle"):
		cycle(1)
		get_viewport().set_input_as_handled()


## Sets the Music volume in dB and saves it.
func set_music_volume_db(db: float) -> void:
	music_volume_db = db
	_apply_volume()
	save()


func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, music_volume_db)


## Loads the remembered station and volume.
func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	var saved := str(cfg.get_value(SECTION, KEY_STATION, station_id))
	if saved == OFF or not variant(saved).is_empty():
		station_id = saved
		chosen_id = saved
	music_volume_db = float(cfg.get_value(SECTION, KEY_VOLUME, music_volume_db))


## Writes the station and volume to settings.cfg, keeping its other sections.
func save() -> Error:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value(SECTION, KEY_STATION, chosen_id)
	cfg.set_value(SECTION, KEY_VOLUME, music_volume_db)
	return cfg.save(settings_path)
