extends GdUnitTestSuite
## Issue reports on disk: building, saving, state, queue, pruning and the browser hand-off.

const ReportSchema := preload("res://tests/report_schema.gd")
const T0 := 1791023700.0  # 2026-10-03T10:35:00Z

var _base: String
var _store: ReportStore


func before_test() -> void:
	_base = "user://tmp/reports_%d" % Time.get_ticks_usec()
	_store = ReportStore.new(_base)


func after_test() -> void:
	for row in _store.list():
		_store.delete(row["id"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_base))


func _place() -> Dictionary:
	var p := Diagnostics.empty_place()
	p.merge({"x": 237.2, "y": 70.4, "z": 17.6, "mode": "car", "road": "Elgin Street", "edge_id": "w435115744.0", "node_id": "c901050337", "time_of_day": "13:10"}, true)
	return p


func _report(fields: Dictionary = {}, has_shot: bool = false, t: float = T0) -> Dictionary:
	var diag := Diagnostics.collect(_place(), [{"id": "code430.ottawa-centretown", "version": "0.1.0"}], {"avg_ms": 9.7, "p99_ms": 15.1, "seconds": 30.0})
	var f := {"area": "roads", "severity": "annoying"}
	f.merge(fields, true)
	return ReportStore.build(f, diag, ["line one", "line two"], has_shot, t)


func test_built_report_fits_the_schema() -> void:
	var report := _report({"description": "Curb inside the junction.", "reporter_id": "3fa9c2d1"})
	assert_array(ReportSchema.check(report, ReportSchema.schema())).is_empty()
	assert_str(report["created_at"]).is_equal("2026-10-03T10:35:00Z")
	assert_bool(RegEx.create_from_string("^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$").search(report["id"]) != null).is_true()


func test_title_is_generated_from_area_severity_and_place() -> void:
	assert_str(_report()["title"]).is_equal("Report: Roads and junctions · Annoying · Elgin Street (x 237, z 18)")
	var off_road := _place()
	off_road["road"] = ""
	assert_str(ReportStore.auto_title("traffic", "cosmetic", off_road)).is_equal("Report: Traffic · Cosmetic (x 237, z 18)")
	assert_str(ReportStore.auto_title("audio", "crash", Diagnostics.empty_place())).is_equal("Report: Audio · Crash")
	# A typed title is not a thing any more: the generated one always wins.
	assert_str(_report({"title": "typed"})["title"]).starts_with("Report: ")


func test_reporter_id_is_random_stable_and_never_sent_unless_chosen() -> void:
	var path := _base + "_reporter_id.txt"
	var first := ReportStore.reporter_id(path)
	assert_bool(RegEx.create_from_string("^[0-9a-f]{8}$").search(first) != null).is_true()
	assert_str(ReportStore.reporter_id(path)).is_equal(first)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_str(_report()["reporter_id"]).is_equal("")


func test_typed_fields_are_trimmed_and_capped() -> void:
	var long_road := _place()
	long_road["road"] = "r".repeat(300)
	var diag := Diagnostics.collect(long_road, [], {"avg_ms": 0.0, "p99_ms": 0.0, "seconds": 0.0})
	var report := ReportStore.build({"area": "roads", "severity": "annoying", "description": "d".repeat(5000)}, diag, [], false, T0)
	assert_int(str(report["title"]).length()).is_equal(ReportStore.TITLE_MAX)
	assert_int(str(report["description"]).length()).is_equal(ReportStore.DESCRIPTION_MAX)


func test_save_load_round_trip_with_downscaled_screenshot() -> void:
	var report := _report({}, true)
	var shot := Image.create(2560, 1600, false, Image.FORMAT_RGB8)
	shot.fill(Color(0.2, 0.5, 0.3))
	var id := _store.save(report, shot)
	var loaded := _store.load_report(id)
	assert_str(loaded["title"]).is_equal(report["title"])
	assert_array(ReportSchema.check(loaded, ReportSchema.schema())).is_empty()
	var path := _store.screenshot_path(id)
	assert_str(path).is_not_empty()
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert_int(img.get_width()).is_equal(1280)
	assert_int(img.get_height()).is_equal(800)
	assert_str(_store.state_of(id)["state"]).is_equal("queued")
	assert_str(FileAccess.get_file_as_string(_base.path_join(id).path_join("log_tail.txt"))).is_equal("line one\nline two")


func test_screenshot_left_out_is_not_saved() -> void:
	var shot := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var id := _store.save(_report({}, false), shot)
	assert_str(_store.screenshot_path(id)).is_empty()


func test_queue_lists_due_reports_oldest_first_and_skips_sent_and_waiting() -> void:
	var a := _store.save(_report({}, false, T0))
	var b := _store.save(_report({}, false, T0 + 60))
	var c := _store.save(_report({}, false, T0 + 120))
	var d := _store.save(_report({}, false, T0 + 180))
	_store.set_state(b, {"state": "sent", "issue_url": "https://github.com/x/y/issues/1", "sent_at": T0})
	_store.set_state(c, {"state": "failed", "error": "429", "retry_at": T0 + 3600})
	assert_array(_store.due(T0 + 600)).is_equal([a, d])
	assert_array(_store.due(T0 + 4000)).is_equal([a, c, d])
	var listed := _store.list()
	assert_str(listed[0]["id"]).is_equal(d)
	assert_str(listed[2]["issue_url"]).is_equal("https://github.com/x/y/issues/1")


func test_prune_deletes_only_old_sent_reports() -> void:
	var old_sent := _store.save(_report({}, false, T0))
	var new_sent := _store.save(_report({}, false, T0 + 60))
	var queued := _store.save(_report({}, false, T0 + 120))
	_store.set_state(old_sent, {"state": "sent", "sent_at": T0})
	_store.set_state(new_sent, {"state": "sent", "sent_at": T0 + 29 * 86400.0})
	assert_int(_store.prune(T0 + 31 * 86400.0)).is_equal(1)
	assert_dict(_store.load_report(old_sent)).is_empty()
	assert_dict(_store.load_report(new_sent)).is_not_empty()
	assert_dict(_store.load_report(queued)).is_not_empty()


func test_handoff_url_is_prefilled_and_short() -> void:
	var report := _report({"description": "x".repeat(4000)})
	var url := ReportStore.handoff_url("rjksn/Code430", report)
	assert_str(url).starts_with("https://github.com/rjksn/Code430/issues/new?labels=in-game-report%2Cneeds-triage%2Carea%3Aroads%2Cseverity%3Aannoying&title=Report%3A%20Roads%20and%20junctions")
	assert_int(url.length()).is_less_equal(ReportStore.HANDOFF_URL_MAX)
	var short := ReportStore.handoff_url("rjksn/Code430", _report({"description": "Curb inside."}))
	assert_str(short.uri_decode()).contains("Curb inside.")
	assert_str(short.uri_decode()).contains("c901050337")
	# A dev build has no date: the build row has no empty gap.
	assert_str(short.uri_decode()).not_contains(", ,")
	# No description: no blank gap where it would go.
	var empty := ReportStore.handoff_url("rjksn/Code430", _report()).uri_decode()
	assert_str(empty).not_contains("\n\n\n")


## Quick tags (human, 2026-10-06): optional, in list order, in the title and the hand-off, and
## absent from untagged reports so those stay exactly as before.
func test_tags_are_optional_ordered_and_fit_the_schema() -> void:
	assert_bool(_report().has("tags")).override_failure_message("an untagged report gained a tags key").is_false()
	var report := _report({"tags": ["police", "stuck", "made_up", "stuck"]})
	assert_array(report["tags"]).is_equal(["stuck", "police"])
	assert_array(ReportSchema.check(report, ReportSchema.schema())).is_empty()
	assert_str(report["title"]).is_equal("Report: Roads and junctions · Annoying · Elgin Street (x 237, z 18) · Stuck, Police")
	assert_str(report["description"]).is_equal("")
	var url := ReportStore.handoff_url("rjksn/Code430", report)
	assert_str(url).contains("tag%3Astuck")
	assert_str(url.uri_decode()).contains("**Tags:** Stuck, Police")


func test_every_tag_id_fits_the_schema_pattern_and_names_follow_the_relay_rule() -> void:
	var table := ReportStore.tags()
	assert_int(table.size()).is_greater_equal(4)
	var pattern := RegEx.create_from_string(str(ReportSchema.schema()["properties"]["tags"]["items"]["pattern"]))
	for t: Dictionary in table:
		assert_bool(pattern.search(t["id"]) != null).override_failure_message("tag id %s breaks the schema pattern" % t["id"]).is_true()
		var words := str(t["id"]).replace("_", " ")
		assert_str(t["label"]).is_equal(words.substr(0, 1).to_upper() + words.substr(1))
