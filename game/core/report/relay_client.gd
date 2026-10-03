class_name RelayClient
extends Node
## Sends saved issue reports to the report relay and records what happened in the store.
##
## `POST <relay_url>/v1/report` as multipart/form-data: `report` (the schema-v1 JSON) and, when
## there is one, `screenshot` (JPEG). The relay answers 201 or 200 with {"issue_url"}; 429 with
## Retry-After; 503 when switched off; 400 or 413 when it refuses the report. Network errors back
## off. Works while the tree is paused, so a report sent from the pause menu still goes. The
## report id is the relay's idempotency key: resending after a lost answer cannot file twice.

signal report_state_changed(id: String, state: Dictionary)

const TIMEOUT_S := 20.0
const RETRY_EVERY_S := 60.0
const BACKOFF_BASE_S := 60.0
const BACKOFF_MAX_S := 3600.0
const DEFAULT_RETRY_AFTER_S := 600.0
const NEVER_S := 10.0 * 365.0 * 86400.0  # refused reports wait for the player, not the timer

var store: ReportStore
var relay_url: String = ""
## Callable(url: String, headers: PackedStringArray, body: PackedByteArray) -> {"code": int,
## "headers": PackedStringArray, "body": String}; code 0 means no answer. Defaults to HTTPRequest.
var transport: Callable
## Seconds since the epoch; tests replace it.
var clock: Callable = func() -> float: return Time.get_unix_time_from_system()

var _sending: Dictionary = {}  # id -> true while a request is out
var _since_retry: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not transport.is_valid():
		transport = _http_post


func _process(delta: float) -> void:
	_since_retry += delta
	if _since_retry >= RETRY_EVERY_S:
		_since_retry = 0.0
		send_due()


## True when a relay URL is configured.
func configured() -> bool:
	return relay_url != ""


## Sends every report that is due, oldest first, one at a time.
func send_due() -> void:
	if not configured() or store == null:
		return
	for id in store.due(clock.call()):
		await send(id)


## Sends one saved report and records the outcome. Returns the new state.
func send(id: String) -> Dictionary:
	var previous := store.state_of(id)
	if not configured():
		return _record(id, {"state": "queued", "error": "no relay configured", "attempts": int(previous.get("attempts", 0))})
	if _sending.has(id) or previous.get("state", "") == "sent":
		return previous
	var report := store.load_report(id)
	if report.is_empty():
		return {}
	_sending[id] = true
	var boundary := "code430-%08x%08x" % [randi(), randi()]
	var body := multipart_body(boundary, report, store.screenshot_path(id))
	var headers := PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary, "Accept: application/json"])
	var url := relay_url.trim_suffix("/") + "/v1/report"
	var answer: Dictionary = await transport.call(url, headers, body)
	_sending.erase(id)
	return _record(id, outcome(answer, int(previous.get("attempts", 0)), clock.call()))


## The state a relay answer leads to. Pure, for tests.
static func outcome(answer: Dictionary, attempts: int, now: float) -> Dictionary:
	var code := int(answer.get("code", 0))
	var tries := attempts + 1
	if code == 200 or code == 201:
		var parsed: Variant = JSON.parse_string(str(answer.get("body", "")))
		var url := str((parsed as Dictionary).get("issue_url", "")) if parsed is Dictionary else ""
		return {"state": "sent", "issue_url": url, "sent_at": now, "attempts": tries}
	if code == 429:
		var wait := _retry_after(answer.get("headers", PackedStringArray()))
		return {"state": "failed", "error": "rate limited", "retry_at": now + wait, "attempts": tries}
	if code == 503:
		return {"state": "queued", "error": "report service switched off", "retry_at": now + DEFAULT_RETRY_AFTER_S, "attempts": tries}
	if code == 400 or code == 413:
		return {"state": "failed", "error": "refused (%d): %s" % [code, str(answer.get("body", "")).substr(0, 200)], "retry_at": now + NEVER_S, "attempts": tries}
	var backoff := minf(BACKOFF_BASE_S * pow(2.0, attempts), BACKOFF_MAX_S)
	var why := "no answer" if code == 0 else "relay error %d" % code
	return {"state": "failed", "error": why, "retry_at": now + backoff, "attempts": tries}


## multipart/form-data with the report JSON and the screenshot JPEG (when the path exists).
static func multipart_body(boundary: String, report: Dictionary, screenshot_path: String) -> PackedByteArray:
	var body := PackedByteArray()
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"report\"\r\nContent-Type: application/json\r\n\r\n" % boundary).to_utf8_buffer())
	body.append_array(JSON.stringify(report).to_utf8_buffer())
	body.append_array("\r\n".to_utf8_buffer())
	if screenshot_path != "" and FileAccess.file_exists(screenshot_path):
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"screenshot\"; filename=\"screenshot.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n" % boundary).to_utf8_buffer())
		body.append_array(FileAccess.get_file_as_bytes(screenshot_path))
		body.append_array("\r\n".to_utf8_buffer())
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
	return body


static func _retry_after(headers: Variant) -> float:
	for h in headers:
		var line := str(h)
		if line.to_lower().begins_with("retry-after:"):
			var v := line.get_slice(":", 1).strip_edges()
			if v.is_valid_float():
				return maxf(1.0, float(v))
	return DEFAULT_RETRY_AFTER_S


func _record(id: String, state: Dictionary) -> Dictionary:
	store.set_state(id, state)
	report_state_changed.emit(id, state)
	return state


func _http_post(url: String, headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var err := http.request_raw(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"code": 0, "headers": PackedStringArray(), "body": ""}
	var res: Array = await http.request_completed
	http.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"code": 0, "headers": PackedStringArray(), "body": ""}
	return {"code": int(res[1]), "headers": res[2], "body": (res[3] as PackedByteArray).get_string_from_utf8()}
