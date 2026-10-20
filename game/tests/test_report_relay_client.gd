extends GdUnitTestSuite
## Sending reports to the relay, against a fake transport: no network in tests.

const T0 := 1791023700.0

var _base: String
var _store: ReportStore
var _client: RelayClient
var _now: float = T0
var _answers: Array = []  # what the fake relay answers, in order
var _calls: Array = []  # [url, headers, body] per request
var _slow: bool = false  # the fake waits a frame before answering, like a real request


func before_test() -> void:
	_base = "user://tmp/relay_reports_%d" % Time.get_ticks_usec()
	_store = ReportStore.new(_base)
	_client = auto_free(RelayClient.new())
	_client.store = _store
	_client.relay_url = "https://relay.example.workers.dev/"
	_client.transport = _fake
	_client.clock = func() -> float: return _now
	add_child(_client)
	_now = T0
	_answers = []
	_calls = []
	_slow = false


func after_test() -> void:
	get_tree().paused = false
	for row in _store.list():
		_store.delete(row["id"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_base))


func _fake(url: String, headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
	_calls.append([url, headers, body])
	if _slow:
		await get_tree().process_frame
	return _answers.pop_front() if not _answers.is_empty() else {"code": 0}


func _save(with_shot: bool = false, t: float = T0) -> String:
	var diag := Diagnostics.collect(Diagnostics.empty_place(), [], FrameTimes.new().stats())
	var report := ReportStore.build({"area": "roads", "severity": "annoying", "title": "t"}, diag, [], with_shot, t)
	var shot: Image = null
	if with_shot:
		shot = Image.create(64, 40, false, Image.FORMAT_RGB8)
	return _store.save(report, shot)


func test_filed_report_is_marked_sent_with_its_issue() -> void:
	var id := _save(true)
	_answers = [{"code": 201, "body": '{"issue_url": "https://github.com/Code430Game/Code430Game/issues/9", "report_id": "%s"}' % id}]
	var state := await _client.send(id)
	assert_str(state["state"]).is_equal("sent")
	assert_str(_store.state_of(id)["issue_url"]).is_equal("https://github.com/Code430Game/Code430Game/issues/9")
	assert_str(_calls[0][0]).is_equal("https://relay.example.workers.dev/v1/report")
	var body: String = (_calls[0][2] as PackedByteArray).get_string_from_ascii()
	assert_str(body).contains('name="report"')
	assert_str(body).contains('"id":"%s"' % id)
	assert_str(body).contains('name="screenshot"; filename="screenshot.jpg"')
	assert_str(str(_calls[0][1][0])).starts_with("Content-Type: multipart/form-data; boundary=code430-")
	# Already sent: nothing goes out again.
	await _client.send(id)
	assert_int(_calls.size()).is_equal(1)


func test_report_without_screenshot_sends_only_the_json() -> void:
	var id := _save(false)
	_answers = [{"code": 200, "body": '{"issue_url": "u"}'}]
	await _client.send(id)
	assert_str((_calls[0][2] as PackedByteArray).get_string_from_ascii()).not_contains('name="screenshot"')


func test_lost_answer_backs_off_then_the_same_report_is_resent() -> void:
	var id := _save()
	_answers = [{"code": 0}]
	var state := await _client.send(id)
	assert_str(state["state"]).is_equal("failed")
	assert_float(state["retry_at"]).is_equal(T0 + RelayClient.BACKOFF_BASE_S)
	assert_array(_store.due(T0 + 1)).is_empty()
	_now = T0 + 120
	_answers = [{"code": 200, "body": '{"issue_url": "https://github.com/Code430Game/Code430Game/issues/9"}'}]
	await _client.send_due()
	assert_str(_store.state_of(id)["state"]).is_equal("sent")
	# Both requests carried the same report id, which is what the relay deduplicates on.
	for call in _calls:
		assert_str((call[2] as PackedByteArray).get_string_from_ascii()).contains('"id":"%s"' % id)


func test_backoff_doubles_and_caps() -> void:
	assert_float(RelayClient.outcome({"code": 502}, 0, 0.0)["retry_at"]).is_equal(60.0)
	assert_float(RelayClient.outcome({"code": 502}, 2, 0.0)["retry_at"]).is_equal(240.0)
	assert_float(RelayClient.outcome({"code": 0}, 20, 0.0)["retry_at"]).is_equal(RelayClient.BACKOFF_MAX_S)


func test_rate_limit_waits_for_retry_after() -> void:
	var id := _save()
	_answers = [{"code": 429, "headers": PackedStringArray(["Content-Type: application/json", "Retry-After: 1800"])}]
	var state := await _client.send(id)
	assert_str(state["error"]).is_equal("rate limited")
	assert_array(_store.due(T0 + 1700)).is_empty()
	assert_array(_store.due(T0 + 1801)).is_equal([id])


func test_switched_off_relay_keeps_the_report_queued() -> void:
	var id := _save()
	_answers = [{"code": 503}]
	var state := await _client.send(id)
	assert_str(state["state"]).is_equal("queued")
	assert_float(state["retry_at"]).is_equal(T0 + RelayClient.DEFAULT_RETRY_AFTER_S)


func test_refused_report_is_not_retried_by_the_timer() -> void:
	var id := _save()
	_answers = [{"code": 400, "body": '{"error": "title too long"}'}]
	var state := await _client.send(id)
	assert_str(state["state"]).is_equal("failed")
	assert_str(state["error"]).contains("title too long")
	assert_array(_store.due(T0 + 30 * 86400.0)).is_empty()


func test_without_a_relay_reports_stay_queued_and_nothing_is_sent() -> void:
	_client.relay_url = ""
	var id := _save()
	var state := await _client.send(id)
	assert_str(state["state"]).is_equal("queued")
	assert_int(_calls.size()).is_equal(0)
	await _client.send_due()
	assert_int(_calls.size()).is_equal(0)


func test_due_reports_go_oldest_first() -> void:
	var newer := _save(false, T0 + 60)
	var older := _save(false, T0)
	_answers = [{"code": 201, "body": "{}"}, {"code": 201, "body": "{}"}]
	await _client.send_due()
	assert_str((_calls[0][2] as PackedByteArray).get_string_from_ascii()).contains(older)
	assert_str((_calls[1][2] as PackedByteArray).get_string_from_ascii()).contains(newer)


func test_sends_while_the_game_is_paused() -> void:
	var id := _save()
	_slow = true
	_answers = [{"code": 201, "body": '{"issue_url": "u"}'}]
	get_tree().paused = true
	var state := await _client.send(id)
	assert_str(state["state"]).is_equal("sent")


func test_state_changes_reach_the_form() -> void:
	var id := _save()
	var seen := []
	_client.report_state_changed.connect(func(rid: String, st: Dictionary) -> void: seen.append([rid, st["state"]]))
	_answers = [{"code": 201, "body": '{"issue_url": "u"}'}]
	await _client.send(id)
	assert_array(seen).is_equal([[id, "sent"]])
