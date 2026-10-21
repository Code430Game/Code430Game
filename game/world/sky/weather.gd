class_name WeatherController
extends Node
## Weather as data: a table of states (weather.v0.json) walked by a seeded Markov pick, with
## every value blended over the state's transition time. Feeds DayNight (clouds, fog, tint),
## the precipitation box, the ground materials (wetness, snow) and the gameplay factors.
##
## Approach: `state` is the settled state and `next_state` the one being blended in; `t` runs
## 0..1 through the transition (1 means settled, when next_state == state). Blended values are
## lerp(state, next, smoothstep(t)). After a state's drawn duration lapses the next one comes
## from the table's weights with the seeded RNG, so the same seed and clock give the same
## sequence (Shared Weather: the host sends state, next, t, seed and elapsed with the clock).

const DATA_PATH := "res://world/sky/weather.v0.json"
const CLOUD_NOISE_SIZE := 512
const CLOUD_NOISE_SEED := 4301
const CLOUD_RECIPE_VERSION := 1

var data: Dictionary = {}
var states: Dictionary = {}
var order: PackedStringArray = PackedStringArray()  # state ids in file order: the snapshot index
var state: String = "clear"
var next_state: String = "clear"
var t: float = 1.0  # transition progress; 1 = settled
var elapsed: float = 0.0  # seconds settled in `state`
var duration: float = 0.0  # drawn length of the settled state
var seed: int = 0
var pinned: bool = false  # --weather=<state>: hold it, never consult the table
var upcoming: String = ""  # the state drawn to follow this one (forecast); "" when pinned or unknown
var mirror: bool = false  # a guest: the host's snapshots drive it, no table here
var bias_wet: bool = false  # ContentMode flag weather_bias: rain and fog weigh more
var hour: float = 12.0  # fed from DayNight; gates snow
var wetness: float = 0.0  # 0 dry .. 1 soaked; rises in rain, dries after
var snow_cover: float = 0.0  # 0 bare .. 1 white; rises in snow, melts after
var wind_speed: float = 2.0
var wind_dir: Vector2 = Vector2(1, 0)
var time: float = 0.0  # seconds since setup, for the cloud scroll
var day_night: DayNight = null
## Outputs, wired by the scene: shared materials that take `wetness` and `snow` uniforms, the
## particle box, the ambience voice (rain hiss) and the traffic manager (speed factor).
var surfaces: Array[ShaderMaterial] = []
var precipitation: Precipitation = null
var ambience: AmbienceAudio = null
var traffic: TrafficManager = null
var speed_table: Dictionary = {}  # traffic_config weather_speed_factor: state -> factor
var _rng := RandomNumberGenerator.new()
var _picks: int = 0  # table consultations (tests)

static var _cloud_cache: ImageTexture = null


func _ready() -> void:
	if data.is_empty():
		load_data()


## Loads the state table. Returns false and logs when the file is missing or malformed.
func load_data(path: String = DATA_PATH) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("states"):
		push_error("Weather: cannot read %s" % path)
		return false
	data = parsed
	states = data["states"]
	order = PackedStringArray(states.keys())
	return true


## Starts the controller: `rng_seed` drives every pick, `start` overrides the table's first
## state, `pin` holds it for the session.
func setup(rng_seed: int, start: String = "", pin: bool = false) -> void:
	if data.is_empty():
		load_data()
	seed = rng_seed
	_rng.seed = rng_seed
	pinned = pin
	var first := start if states.has(start) else str(data.get("start", "clear"))
	state = first
	next_state = first
	t = 1.0
	elapsed = 0.0
	time = 0.0
	_picks = 0
	# A pinned wet or snowy start has been going on a while: the ground already shows it.
	wetness = 1.0 if pin and first == "rain" else 0.0
	snow_cover = 1.0 if pin and first == "snow" else 0.0
	_enter(first)


## Blends to `id` over its transition and holds it (the Testing tab, add-world-menu): the
## table isn't consulted until `release()`. Snow is allowed at any hour when held.
func hold(id: String) -> void:
	if not states.has(id):
		return
	if t < 1.0 and t >= 0.5:
		state = next_state  # mid-blend: carry on from the nearer end
	pinned = true
	upcoming = ""
	elapsed = 0.0
	if id == state:
		next_state = state
		t = 1.0
	else:
		next_state = id
		t = 0.0


## Lets the table walk again from the current state (the Testing tab's Auto).
func release() -> void:
	if not pinned:
		return
	pinned = false
	if t >= 1.0:
		elapsed = 0.0
		_enter(state)


func _enter(id: String) -> void:
	var s: Dictionary = states[id]
	var d: Array = s.get("duration_s", [600, 600])
	duration = _rng.randf_range(float(d[0]), float(d[1]))
	var w: Array = s.get("wind", [1, 3])
	wind_speed = _rng.randf_range(float(w[0]), float(w[1]))
	var ang := _rng.randf_range(0.0, TAU)
	wind_dir = Vector2(cos(ang), sin(ang))
	# The follower is drawn now rather than at the end of the state, so the HUD can show a
	# forecast; a pinned session or a guest never consults the table.
	upcoming = pick_next() if not pinned and not mirror else ""


func _process(delta: float) -> void:
	if day_night != null:
		hour = day_night.hour
	step(delta)
	apply_outputs()


## Pushes the blended values to everything wired in: the sky, the surfaces, the particles,
## the rain bed and traffic. Called once per frame; safe to call from tests after step().
func apply_outputs() -> void:
	if day_night != null:
		day_night.weather_coverage = coverage()
		day_night.weather_fog = fog()
		day_night.weather_tint = tint()
		day_night.weather_wind = wind_dir * wind_speed
		day_night.weather_time = time
	for m in surfaces:
		m.set_shader_parameter("wetness", wetness)
		m.set_shader_parameter("snow", snow_cover)
	if precipitation != null:
		var kind := "snow" if _is_snow_state() else "rain"
		if precipitation.kind != kind:
			precipitation.set_kind(kind)
		precipitation.set_wind(Vector3(wind_dir.x, 0.0, wind_dir.y) * wind_speed)
		precipitation.set_intensity(precip())
	if ambience != null:
		ambience.rain = precip() if _is_wet_state() else 0.0
	if traffic != null and not speed_table.is_empty():
		traffic.weather_speed_factor = speed_factor(speed_table)


## Advances the weather by `delta` seconds: transitions, the table, wetness and snow cover.
func step(delta: float) -> void:
	time += delta
	if t < 1.0:
		# A transition blends on every peer; only the host (or a solo session) walks the table.
		var tr := float(states[next_state].get("transition_s", 120.0))
		t = minf(t + delta / maxf(tr, 0.01), 1.0)
		if t >= 1.0:
			state = next_state
			elapsed = 0.0
			if not mirror:
				_enter(state)
	elif not pinned and not mirror:
		elapsed += delta
		if elapsed >= duration:
			# Snow drawn hours ago may no longer be allowed: draw again in that case.
			var nxt := upcoming if upcoming != "" and (upcoming != "snow" or snow_allowed()) else pick_next()
			if nxt == state:
				elapsed = 0.0
				_enter(state)
			else:
				next_state = nxt
				t = 0.0
	_accumulate(delta)


func _accumulate(delta: float) -> void:
	var raining := precip() * (1.0 if _is_wet_state() else 0.0)
	var snowing := precip() * (1.0 if _is_snow_state() else 0.0)
	wetness = _toward(wetness, raining, delta, float(data.get("wetness_rise_s", 60.0)), float(data.get("wetness_dry_s", 900.0)))
	snow_cover = _toward(snow_cover, snowing, delta, float(data.get("snow_rise_s", 300.0)), float(data.get("snow_melt_s", 1800.0)))


static func _toward(v: float, target: float, delta: float, rise_s: float, fall_s: float) -> float:
	if target > v:
		return minf(v + delta / maxf(rise_s, 0.01), target)
	return maxf(v - delta / maxf(fall_s, 0.01), target)


func _is_wet_state() -> bool:
	return state == "rain" or next_state == "rain"


func _is_snow_state() -> bool:
	return state == "snow" or next_state == "snow"


## Picks the next state from the settled state's weights with the seeded RNG. Snow is only
## eligible between snow_hours; a wet bias (dystopia) doubles rain and fog.
func pick_next() -> String:
	_picks += 1
	var row: Dictionary = states[state].get("next", {})
	var ids: Array = []
	var weights: Array = []
	var total := 0.0
	for id in row:
		if id == "snow" and not snow_allowed():
			continue
		var w := float(row[id])
		if bias_wet and (id == "rain" or id == "fog"):
			w *= float(data.get("bias_wet_weight", 2.0))
		ids.append(id)
		weights.append(w)
		total += w
	if ids.is_empty() or total <= 0.0:
		return state
	var r := _rng.randf() * total
	for i in range(ids.size()):
		r -= float(weights[i])
		if r <= 0.0:
			return str(ids[i])
	return str(ids[ids.size() - 1])


## True in the evening-to-morning window the data names, until a season table exists.
func snow_allowed() -> bool:
	var hours: Array = data.get("snow_hours", [20, 7])
	var from := float(hours[0])
	var to := float(hours[1])
	if from <= to:
		return hour >= from and hour < to
	return hour >= from or hour < to


func _blend(key: String, fallback: float) -> float:
	var a := float(states[state].get(key, fallback))
	var b := float(states[next_state].get(key, fallback))
	return lerpf(a, b, smoothstep(0.0, 1.0, t))


func coverage() -> float:
	return _blend("coverage", 0.0)


func precip() -> float:
	return _blend("precip", 0.0)


func fog() -> float:
	return _blend("fog", 0.0)


## The player's tyre grip multiplier for the blended state.
func grip_factor() -> float:
	return _blend("grip", 1.0)


## 0..1: how much the headlight auto mode should treat the weather as dusk.
func headlight_need() -> float:
	return _blend("headlights", 0.0)


## Traffic's speed multiplier from a {state: factor} table, blended like the rest.
func speed_factor(table: Dictionary) -> float:
	var a := float(table.get(state, 1.0))
	var b := float(table.get(next_state, 1.0))
	return lerpf(a, b, smoothstep(0.0, 1.0, t))


func tint() -> Color:
	var a := _c(states[state].get("tint", [1, 1, 1]))
	var b := _c(states[next_state].get("tint", [1, 1, 1]))
	return a.lerp(b, smoothstep(0.0, 1.0, t))


func temp_c() -> float:
	var a: Array = states[state].get("temp_c", [10, 10])
	var b: Array = states[next_state].get("temp_c", [10, 10])
	return lerpf((float(a[0]) + float(a[1])) * 0.5, (float(b[0]) + float(b[1])) * 0.5, smoothstep(0.0, 1.0, t))


## True while rain or snow is falling at all (particles, sound).
func precipitating() -> bool:
	return precip() > 0.001


func is_snowing() -> bool:
	return _is_snow_state() and precip() > 0.001


## The host's view of the weather for the clock sync: state, next, t, seed, elapsed.
func snapshot() -> PackedFloat32Array:
	return PackedFloat32Array([float(order.find(state)), float(order.find(next_state)), t, float(seed), elapsed, float(order.find(upcoming)), duration])


## A guest takes the host's snapshot and keeps blending locally from it.
func apply_snapshot(p: PackedFloat32Array) -> void:
	if p.size() < 5 or order.is_empty():
		return
	var si := clampi(int(p[0]), 0, order.size() - 1)
	var ni := clampi(int(p[1]), 0, order.size() - 1)
	var new_state := order[si]
	var new_next := order[ni]
	if new_state != state or new_next != next_state or int(p[3]) != seed:
		seed = int(p[3])
		_rng.seed = seed
		state = new_state
		next_state = new_next
	t = clampf(p[2], 0.0, 1.0)
	elapsed = p[4]
	if p.size() >= 7:
		var ui := int(p[5])
		upcoming = order[ui] if ui >= 0 and ui < order.size() else ""
		duration = p[6]


## The forecast for the HUD: the state now, what follows (the transition's target while one
## runs, else the drawn follower, "" when unknown), whether a change is under way, and the
## real seconds left before the next change starts (weather runs on real time).
func forecast() -> Dictionary:
	var changing := t < 1.0 and next_state != state
	var follower := next_state if changing else upcoming
	if follower == state:
		follower = ""
	return {"state": state, "next": follower, "changing": changing, "seconds_left": maxf(duration - elapsed, 0.0) if not changing else 0.0}


## Short text for the HUD and logs, e.g. "rain" or "overcast > rain 40%".
func describe() -> String:
	if t >= 1.0 or next_state == state:
		return state
	return "%s > %s %d%%" % [state, next_state, int(t * 100.0)]


## Count of table picks so far (tests: a pinned session never consults the table).
func picks() -> int:
	return _picks


static func _c(v: Variant) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return Color.WHITE


## Seamless cloud noise for the sky shader and the sun's shadow projector: built once from a
## fixed seed (byte-identical everywhere), cached as a PNG in user:// like the ground detail.
static func cloud_noise_texture(size: int = CLOUD_NOISE_SIZE) -> ImageTexture:
	if _cloud_cache != null and _cloud_cache.get_width() == size:
		return _cloud_cache
	var path := "user://cache/cloud_noise_v%d_%d.png" % [CLOUD_RECIPE_VERSION, size]
	var img: Image = null
	if FileAccess.file_exists(path):
		img = Image.load_from_file(path)
	if img == null or img.get_width() != size:
		img = build_cloud_image(size)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cache"))
		img.save_png(path)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	_cloud_cache = ImageTexture.create_from_image(img)
	return _cloud_cache


## Fresh cloud noise image: five-octave FBM, seamless, so banks tile without a seam.
static func build_cloud_image(size: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = CLOUD_NOISE_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.55
	noise.frequency = 2.2 / float(size)
	var img := noise.get_seamless_image(size, size, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	return img
