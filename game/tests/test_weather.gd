extends GdUnitTestSuite
## The weather table: determinism by seed, blends, the pinned state, the snow gate, wetness
## and snow cover, and the host snapshot a guest follows.


func _controller(seed: int, start: String = "", pin: bool = false) -> WeatherController:
	var w: WeatherController = auto_free(WeatherController.new())
	add_child(w)
	w.set_process(false)  # tests step it themselves
	w.setup(seed, start, pin)
	return w


## Runs `w` for `seconds` in one-second steps and returns the sequence of settled states.
func _sequence(w: WeatherController, seconds: int, hour: float) -> PackedStringArray:
	var seen := PackedStringArray([w.state])
	w.hour = hour
	for i in range(seconds):
		w.step(1.0)
		if w.t >= 1.0 and seen[seen.size() - 1] != w.state:
			seen.append(w.state)
	return seen


func test_same_seed_gives_the_same_sequence_and_another_seed_differs() -> void:
	var a := _sequence(_controller(7), 6 * 3600, 12.0)
	var b := _sequence(_controller(7), 6 * 3600, 12.0)
	assert_array(Array(a)).is_equal(Array(b))
	assert_int(a.size()).is_greater(3)  # six hours walks the table several times
	var c := _sequence(_controller(8), 6 * 3600, 12.0)
	assert_bool(Array(a) == Array(c)).is_false()


func test_values_blend_through_the_transition() -> void:
	var w := _controller(1, "clear")
	w.next_state = "overcast"
	w.t = 0.0
	assert_float(w.coverage()).is_equal_approx(0.15, 1e-6)
	w.t = 0.5
	assert_float(w.coverage()).is_equal_approx(0.5, 1e-6)  # smoothstep(0.5) is 0.5
	assert_str(w.describe()).is_equal("clear > overcast 50%")
	w.t = 1.0
	assert_float(w.coverage()).is_equal_approx(0.85, 1e-6)


func test_a_pinned_state_never_consults_the_table() -> void:
	var w := _controller(3, "rain", true)
	w.hour = 12.0
	for i in range(4 * 3600):
		w.step(1.0)
	assert_str(w.state).is_equal("rain")
	assert_str(w.next_state).is_equal("rain")
	assert_int(w.picks()).is_equal(0)
	assert_float(w.precip()).is_equal(1.0)
	assert_float(w.grip_factor()).is_equal_approx(0.8, 1e-6)
	assert_float(w.headlight_need()).is_equal(1.0)


func test_snow_is_only_picked_in_the_cold_hours() -> void:
	var at_noon := 0
	var at_night := 0
	for seed in range(200):
		var w := _controller(seed, "overcast")
		w.hour = 12.0
		if w.pick_next() == "snow":
			at_noon += 1
		w.hour = 23.0
		if w.pick_next() == "snow":
			at_night += 1
	assert_int(at_noon).is_equal(0)
	assert_int(at_night).is_greater(5)


func test_wet_bias_weighs_rain_and_fog() -> void:
	var plain := 0
	var biased := 0
	for seed in range(300):
		var w := _controller(seed, "overcast")
		w.hour = 12.0
		var p := w.pick_next()
		plain += 1 if p == "rain" or p == "fog" else 0
		var b := _controller(seed, "overcast")
		b.hour = 12.0
		b.bias_wet = true
		var q := b.pick_next()
		biased += 1 if q == "rain" or q == "fog" else 0
	assert_int(biased).is_greater(plain)


func test_wetness_rises_in_rain_and_dries_after() -> void:
	var w := _controller(2, "rain")  # not pinned: the ground starts dry and soaks over 60 s
	assert_float(w.wetness).is_equal(0.0)
	for i in range(30):
		w.step(1.0)
	assert_float(w.wetness).is_equal_approx(0.5, 0.01)
	for i in range(90):
		w.step(1.0)
	assert_float(w.wetness).is_equal(1.0)
	assert_float(w.snow_cover).is_equal(0.0)
	assert_float(_controller(2, "rain", true).wetness).is_equal(1.0)  # pinned: already soaked
	w.pinned = false
	w.state = "clear"
	w.next_state = "clear"
	w.pinned = true
	for i in range(450):
		w.step(1.0)
	assert_float(w.wetness).is_equal_approx(0.5, 0.01)  # dries over 900 s
	var s := _controller(2, "snow")
	for i in range(600):
		s.step(1.0)
	assert_float(s.snow_cover).is_greater(0.99)
	assert_bool(s.is_snowing()).is_true()


func test_a_guest_follows_the_host_snapshot() -> void:
	var host := _controller(11, "overcast")
	host.hour = 12.0
	host.next_state = "rain"
	host.t = 0.25
	host.elapsed = 33.0
	var guest := _controller(99, "clear")
	guest.mirror = true
	guest.apply_snapshot(host.snapshot())
	assert_str(guest.state).is_equal("overcast")
	assert_str(guest.next_state).is_equal("rain")
	assert_float(guest.t).is_equal_approx(0.25, 1e-6)
	assert_int(guest.seed).is_equal(11)
	assert_float(guest.coverage()).is_equal_approx(host.coverage(), 1e-6)
	# A mirror keeps blending but never walks the table on its own.
	for i in range(3600):
		guest.step(1.0)
	assert_int(guest.picks()).is_equal(0)
	assert_str(guest.state).is_equal("rain")


func test_outputs_reach_the_surfaces_the_particles_and_the_rain_bed() -> void:
	var w := _controller(5, "rain", true)
	var road := SurfaceDetail.material("asphalt", 0.9)
	var terrain := ShaderMaterial.new()
	terrain.shader = load("res://world/terrain/terrain.gdshader")
	w.surfaces = [road, terrain]
	var p: Precipitation = auto_free(Precipitation.new())
	add_child(p)
	w.precipitation = p
	var amb: AmbienceAudio = auto_free(AmbienceAudio.new())
	amb.muted = true
	add_child(amb)
	w.ambience = amb
	for i in range(120):
		w.step(1.0)
	w.apply_outputs()
	assert_float(float(road.get_shader_parameter("wetness"))).is_equal(1.0)
	assert_float(float(terrain.get_shader_parameter("snow"))).is_equal(0.0)
	assert_str(p.kind).is_equal("rain")
	assert_bool(p.emitting).is_true()
	assert_float(amb.rain).is_equal(1.0)
	var s := _controller(5, "snow", true)
	s.surfaces = [terrain]
	s.precipitation = p
	s.ambience = amb
	for i in range(600):
		s.step(1.0)
	s.apply_outputs()
	assert_float(float(terrain.get_shader_parameter("snow"))).is_greater(0.99)
	assert_str(p.kind).is_equal("snow")
	assert_float(amb.rain).is_equal(0.0)  # snow falls silently


func test_weather_slows_traffic_cuts_grip_and_lights_the_headlights() -> void:
	var w := _controller(4, "snow", true)
	var table := {"clear": 1.0, "rain": 0.85, "snow": 0.7, "fog": 0.8}
	assert_float(w.speed_factor(table)).is_equal_approx(0.7, 1e-6)
	w.next_state = "clear"
	w.t = 0.5
	assert_float(w.speed_factor(table)).is_equal_approx(0.85, 1e-6)
	assert_float(w.grip_factor()).is_equal_approx(0.775, 1e-6)
	assert_float(w.headlight_need()).is_equal_approx(0.5, 1e-6)
	var car: VehicleBody3D = auto_free(load("res://actors/vehicles/placeholder_car.tscn").instantiate())
	add_child(car)
	var wheel := car.get_node("WheelFL") as VehicleWheel3D
	var dry := wheel.wheel_friction_slip
	car.set_grip_factor(0.55)
	assert_float(wheel.wheel_friction_slip).is_equal_approx(dry * 0.55, 1e-5)
	car.set_grip_factor(1.0)
	assert_float(wheel.wheel_friction_slip).is_equal_approx(dry, 1e-5)


func test_the_clock_sync_carries_the_weather_to_a_mirrored_controller() -> void:
	var host := _controller(21, "overcast")
	host.next_state = "fog"
	host.t = 0.4
	var guest := _controller(1, "clear")
	var sync: WorldSync = auto_free(WorldSync.new())
	sync.weather = guest
	add_child(sync)
	sync._signal_time(12.5, -1.0, host.snapshot())
	assert_bool(guest.mirror).is_true()
	assert_str(guest.describe()).is_equal("overcast > fog 40%")
	assert_float(guest.fog()).is_equal_approx(host.fog(), 1e-6)
	sync._signal_time(13.0, -1.0)  # an old host sends no weather: the guest keeps its own
	assert_str(guest.state).is_equal("overcast")


func test_cloud_noise_is_seamless_and_deterministic() -> void:
	var a := WeatherController.build_cloud_image(64)
	var b := WeatherController.build_cloud_image(64)
	assert_bool(a.get_data() == b.get_data()).is_true()
	assert_int(a.get_width()).is_equal(64)
	assert_int(a.get_format()).is_equal(Image.FORMAT_L8)
	var shader: Shader = load("res://world/sky/sky.gdshader")
	var names := PackedStringArray()
	for u in shader.get_shader_uniform_list():
		names.append(str(u["name"]))
	assert_bool(names.has("cloud_coverage")).is_true()
	assert_bool(names.has("cloud_noise")).is_true()
