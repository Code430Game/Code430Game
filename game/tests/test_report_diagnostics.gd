extends GdUnitTestSuite
## Issue report diagnostics: redaction, place, log tail, frame times, and the schema they must fit.

const SCHEMA_PATH := "res://../docs/report-format/report.schema.v1.json"

var _tmp: String


func before_test() -> void:
	_tmp = "user://tmp/diag_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_tmp))


func after_test() -> void:
	var dir := ProjectSettings.globalize_path(_tmp)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


static func schema() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(SCHEMA_PATH)))


## Errors for `value` against a JSON Schema node: required, additionalProperties false, enum,
## const, type, min/max length and items. Enough for the report schema, not a general validator.
static func check(value: Variant, node: Dictionary, at: String = "$") -> Array:
	var errors := []
	if node.has("const") and value != node["const"]:
		errors.append("%s: expected %s" % [at, node["const"]])
	if node.has("enum") and not (value in node["enum"]):
		errors.append("%s: %s not in %s" % [at, value, node["enum"]])
	match str(node.get("type", "")):
		"object":
			if not value is Dictionary:
				return errors + ["%s: not an object" % at]
			for k in node.get("required", []):
				if not (value as Dictionary).has(k):
					errors.append("%s: missing %s" % [at, k])
			var props: Dictionary = node.get("properties", {})
			for k in value:
				if not props.has(k):
					errors.append("%s: unknown key %s" % [at, k])
				else:
					errors += check(value[k], props[k], "%s.%s" % [at, k])
		"array":
			if not value is Array:
				return errors + ["%s: not an array" % at]
			if node.has("maxItems") and (value as Array).size() > int(node["maxItems"]):
				errors.append("%s: too many items" % at)
			if node.has("items"):
				for i in range((value as Array).size()):
					errors += check(value[i], node["items"], "%s[%d]" % [at, i])
		"string":
			if not value is String:
				return errors + ["%s: not a string" % at]
			if (value as String).length() > int(node.get("maxLength", 1 << 30)) or (value as String).length() < int(node.get("minLength", 0)):
				errors.append("%s: length %d out of range" % [at, (value as String).length()])
		"integer":
			if not (value is int or (value is float and float(value) == floorf(value))):
				errors.append("%s: not an integer" % at)
		"number":
			if not (value is int or value is float):
				errors.append("%s: not a number" % at)
		"boolean":
			if not value is bool:
				errors.append("%s: not a boolean" % at)
	return errors


func test_redactor_replaces_home_and_account_name() -> void:
	var r := Diagnostics.Redactor.new("/Users/rjackson", "rjackson")
	assert_str(r.redact("loaded /Users/rjackson/Games/code430/packs as rjackson")).is_equal("loaded ~/Games/code430/packs as <user>")
	assert_str(r.redact("RJackson logged in")).is_equal("<user> logged in")
	assert_str(r.redact("rjacksonville")).is_equal("rjacksonville")  # whole words only


func test_generic_deck_account_keeps_words_but_not_home() -> void:
	var r := Diagnostics.Redactor.new("/home/deck", "deck")
	assert_str(r.redact("preset deck, deck detected, /home/deck/Games")).is_equal("preset deck, deck detected, ~/Games")


func test_account_names_with_regex_characters_are_literal() -> void:
	var r := Diagnostics.Redactor.new("/home/a.b+c", "a.b+c")
	assert_str(r.redact("user a.b+c here, not axb+c")).is_equal("user <user> here, not axb+c")


func test_redact_value_reaches_nested_strings() -> void:
	var r := Diagnostics.Redactor.new("/home/sam", "samuel")
	var v: Dictionary = r.redact_value({"a": ["/home/sam/x", {"b": "samuel"}], "n": 3})
	assert_str(v["a"][0]).is_equal("~/x")
	assert_str(v["a"][1]["b"]).is_equal("<user>")
	assert_int(v["n"]).is_equal(3)


func test_frame_times_average_and_p99() -> void:
	var ft := FrameTimes.new()
	for i in range(99):
		ft.push(0.010)
	ft.push(0.050)
	var s := ft.stats(30.0)
	assert_float(s["avg_ms"]).is_equal_approx(10.4, 0.01)
	assert_float(s["p99_ms"]).is_equal_approx(10.0, 0.01)
	assert_float(s["seconds"]).is_equal_approx(1.0, 0.05)


func test_frame_times_window_keeps_only_recent_frames() -> void:
	var ft := FrameTimes.new()
	for i in range(100):
		ft.push(0.1)  # 10 s of slow frames
	for i in range(100):
		ft.push(0.01)  # then 1 s of fast ones
	var s := ft.stats(1.0)
	assert_float(s["avg_ms"]).is_equal_approx(10.0, 0.01)
	assert_float(s["seconds"]).is_equal_approx(1.0, 0.05)


func test_frame_times_empty() -> void:
	assert_float(FrameTimes.new().stats()["avg_ms"]).is_equal(0.0)


func _graph() -> RoadGraph:
	var nodes := [
		{"id": "n_a", "position": [0, 0, 0], "ground_y": 0, "junction_type": "junction"},
		{"id": "n_b", "position": [100, 0, 0], "ground_y": 0, "junction_type": "dead_end"},
	]
	var edges := [{
		"id": "w1.0", "from": "n_a", "to": "n_b", "polyline": [[0, 0, 0], [100, 0, 0]], "class": "secondary",
		"lanes_forward": 1, "lanes_backward": 1, "oneway": false, "speed_kph": 50, "width_m": 7.0, "layer": 0,
		"bridge": false, "tunnel": false, "name": "Elgin Street", "osm_way_id": 1, "defaulted_fields": [],
		"access": null, "length_m": 100.0,
	}]
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": []})


func test_place_names_road_edge_and_nearest_node() -> void:
	var body := Node3D.new()
	add_child(body)
	body.global_position = Vector3(12.0, 1.0, 2.0)
	body.look_at(Vector3(112.0, 1.0, 2.0))  # facing +x: 90 degrees clockwise from -z
	var place := Diagnostics.place_for(_graph(), body, true, "13:10")
	assert_str(place["road"]).is_equal("Elgin Street")
	assert_str(place["edge_id"]).is_equal("w1.0")
	assert_str(place["node_id"]).is_equal("n_a")
	assert_str(place["mode"]).is_equal("car")
	assert_float(place["heading_deg"]).is_equal_approx(90.0, 0.2)
	assert_float(place["x"]).is_equal_approx(12.0, 0.01)
	assert_str(place["time_of_day"]).is_equal("13:10")
	body.queue_free()


func test_place_far_from_roads_has_no_road() -> void:
	var body := Node3D.new()
	add_child(body)
	body.global_position = Vector3(50.0, 0.0, 500.0)
	var place := Diagnostics.place_for(_graph(), body, false, "")
	assert_str(place["road"]).is_equal("")
	assert_str(place["mode"]).is_equal("foot")
	body.queue_free()


func test_log_tail_keeps_last_lines_redacted() -> void:
	var path := _tmp.path_join("godot.log")
	var f := FileAccess.open(path, FileAccess.WRITE)
	for i in range(300):
		f.store_line("line %d from /home/sam/game" % i)
	f.close()
	var tail := Diagnostics.log_tail(Diagnostics.Redactor.new("/home/sam", "samuel"), path, 200)
	assert_int(tail.size()).is_equal(200)
	assert_str(tail[0]).is_equal("line 100 from ~/game")
	assert_str(tail[199]).is_equal("line 299 from ~/game")


func test_log_tail_cuts_long_lines_and_handles_missing_file() -> void:
	var path := _tmp.path_join("long.log")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("x".repeat(2000))
	f.close()
	var tail := Diagnostics.log_tail(Diagnostics.Redactor.new("", ""), path)
	assert_int(tail.size()).is_equal(1)
	assert_int(str(tail[0]).length()).is_equal(Diagnostics.LOG_LINE_MAX)
	assert_array(Diagnostics.log_tail(null, _tmp.path_join("missing.log"))).is_empty()


func test_collected_diagnostics_fit_the_schema() -> void:
	var body := Node3D.new()
	add_child(body)
	body.global_position = Vector3(10.0, 0.0, 0.0)
	var place := Diagnostics.place_for(_graph(), body, false, "09:30")
	var diag := Diagnostics.collect(place, [{"id": "code430.ottawa-centretown", "version": "0.1.0"}], FrameTimes.new().stats())
	var node: Dictionary = schema()["properties"]["diagnostics"]
	assert_array(check(diag, node)).is_empty()
	assert_str(diag["build"]["source"]).is_equal("dev")
	assert_str(diag["session"]["role"]).is_equal("single")
	body.queue_free()


func test_collected_diagnostics_never_contain_the_home_directory() -> void:
	var home := OS.get_environment("HOME")
	var diag := Diagnostics.collect({}, [], FrameTimes.new().stats())
	if home.length() > 1:
		assert_bool(JSON.stringify(diag).contains(home)).is_false()
	assert_str(diag["place"]["mode"]).is_equal("none")


func test_schema_check_catches_bad_diagnostics() -> void:
	var node: Dictionary = schema()["properties"]["diagnostics"]
	var diag := Diagnostics.collect({}, [], FrameTimes.new().stats())
	diag["session"]["role"] = "spectator"
	diag["machine"]["serial"] = "x"
	(diag["settings"] as Dictionary).erase("preset")
	var errors := check(diag, node)
	assert_int(errors.size()).is_equal(3)
