class_name ReportStore
extends RefCounted
## Issue reports on disk, before and after they are sent.
##
## Each report lives in `<base>/<id>/`: `report.json` (exactly the schema in
## docs/report-format/report.schema.v1.json, the thing the relay receives), `state.json` (queued,
## sent with the issue URL, or failed with the last error and when to retry), `screenshot.jpg` and
## `log_tail.txt`. A report is saved before anything tries to send it, so it is never lost.

const DEFAULT_BASE := "user://reports"
const KEEP_SENT_DAYS := 30
const SCREENSHOT_MAX := Vector2i(1280, 800)
const SCREENSHOT_QUALITY := 0.8
const TITLE_MAX := 120
const DESCRIPTION_MAX := 4000
## A random id made once per install (never derived from the hardware), included only when the
## player chooses, so reports from one install can be told apart without naming anyone. The
## relay posts it only as a keyed one-way hash, so the public issue can't be matched to this file.
const REPORTER_ID_PATH := "user://reporter_id.txt"
## GitHub's new-issue page takes the body in the URL; keep the encoded URL under about 8 KB.
const HANDOFF_URL_MAX := 7500

## Areas and severities in menu order; ids are the schema enums and the label suffixes.
const AREAS := [
	["roads", "Roads and junctions"], ["traffic", "Traffic"], ["pedestrians", "Pedestrians"],
	["vehicles", "Vehicles and handling"], ["world", "Buildings and world"], ["visuals", "Visuals"],
	["performance", "Performance"], ["controls", "Controls and menus"], ["audio", "Audio"],
	["crash", "Crash or freeze"], ["other", "Other"],
]
const SEVERITIES := [["cosmetic", "Cosmetic"], ["annoying", "Annoying"], ["blocks_play", "Blocks play"], ["crash", "Crash"]]
## The quick tags the form offers, [{"id", "label"}] in display order.
const TAGS_PATH := "res://ui/report/report_tags.json"

var base: String


func _init(base_dir: String = DEFAULT_BASE) -> void:
	base = base_dir


## Display label for an area or severity id.
static func label_of(table: Array, id: String) -> String:
	for row in table:
		if row[0] == id:
			return row[1]
	return id


## The quick tags from `TAGS_PATH`: [{"id", "label"}] in display order ([] when missing).
static func tags(path: String = TAGS_PATH) -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var out := []
	if data is Dictionary:
		for t: Variant in (data as Dictionary).get("tags", []):
			if t is Dictionary and str(t.get("id", "")) != "":
				out.append({"id": str(t["id"]), "label": str(t.get("label", t["id"]))})
	return out


## `picked` as known tag ids in the list's order, each once; unknown ids are dropped.
static func ordered_tags(picked: Array, table: Array = tags()) -> Array:
	var out := []
	for t: Dictionary in table:
		if t["id"] in picked and not (t["id"] in out):
			out.append(t["id"])
	return out


## Display labels for tag ids ("stuck" -> "Stuck"); an id not in the list shows as itself.
static func tag_labels(ids: Array, table: Array = tags()) -> PackedStringArray:
	var out := PackedStringArray()
	for id: Variant in ids:
		var label := str(id)
		for t: Dictionary in table:
			if t["id"] == str(id):
				label = t["label"]
		out.append(label)
	return out


## "Report: Roads and junctions · Annoying · Elgin Street (x 237, z 18) · Stuck, Police": every
## report's title, made from what the player chose and where they were. Tags go last, so a long
## title loses them before the place.
static func auto_title(area: String, severity: String, place: Dictionary, tag_ids: Array = [], table: Array = tags()) -> String:
	var title := "Report: %s · %s" % [label_of(AREAS, area), label_of(SEVERITIES, severity)]
	if str(place.get("mode", "none")) != "none":
		var at := "x %d, z %d" % [roundi(float(place["x"])), roundi(float(place["z"]))]
		var road := str(place.get("road", ""))
		title += " · %s (%s)" % [road, at] if road != "" else " (%s)" % at
	if not tag_ids.is_empty():
		title += " · " + ", ".join(tag_labels(tag_ids, table))
	return title.substr(0, TITLE_MAX)


## This install's reporter id, made on first use: eight random hex digits.
static func reporter_id(path: String = REPORTER_ID_PATH) -> String:
	if FileAccess.file_exists(path):
		var saved := FileAccess.get_file_as_string(path).strip_edges()
		if RegEx.create_from_string("^[0-9a-f]{8}$").search(saved) != null:
			return saved
	var made := "%08x" % randi()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(made)
		f.close()
	return made


## Throws away this install's reporter id and makes a new one, so later reports no longer link to
## earlier ones. Returns the new id.
static func regenerate_reporter_id(path: String = REPORTER_ID_PATH) -> String:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return reporter_id(path)


## A new report id: UTC timestamp plus eight random hex digits.
static func new_id(unix_time: float = Time.get_unix_time_from_system()) -> String:
	var t := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return "%04d%02d%02dT%02d%02d%02dZ-%08x" % [t.year, t.month, t.day, t.hour, t.minute, t.second, randi()]


## Builds the report dictionary (schema version 1) from what the player chose and the diagnostics.
## `tags` is present only when the player picked some, so an untagged report is exactly as before.
static func build(fields: Dictionary, diagnostics: Dictionary, log_tail: Array, has_screenshot: bool, unix_time: float = Time.get_unix_time_from_system()) -> Dictionary:
	var area := str(fields.get("area", "other"))
	var severity := str(fields.get("severity", "annoying"))
	var picked := ordered_tags(fields.get("tags", []))
	var title := auto_title(area, severity, diagnostics.get("place", {}), picked)
	var t := Time.get_datetime_dict_from_unix_time(int(unix_time))
	var report := {
		"version": 1,
		"id": new_id(unix_time),
		"created_at": "%04d-%02d-%02dT%02d:%02d:%02dZ" % [t.year, t.month, t.day, t.hour, t.minute, t.second],
		"title": title.substr(0, TITLE_MAX),
		"description": Diagnostics.Redactor.scrub(str(fields.get("description", "")).strip_edges().substr(0, DESCRIPTION_MAX)),
		"area": area,
		"severity": severity,
		"reporter_id": str(fields.get("reporter_id", "")),
		"has_screenshot": has_screenshot,
		"diagnostics": diagnostics,
		"log_tail": log_tail,
	}
	if not picked.is_empty():
		report["tags"] = picked
	return report


## Saves a report and its screenshot (downscaled, JPEG) as queued. Returns the report id.
func save(report: Dictionary, screenshot: Image = null) -> String:
	var dir := _dir(report["id"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_write(dir.path_join("report.json"), JSON.stringify(report, "  ", false))
	_write(dir.path_join("log_tail.txt"), "\n".join(PackedStringArray(report.get("log_tail", []))))
	if screenshot != null and bool(report.get("has_screenshot", false)):
		var img := screenshot.duplicate() as Image
		var scale := minf(1.0, minf(float(SCREENSHOT_MAX.x) / img.get_width(), float(SCREENSHOT_MAX.y) / img.get_height()))
		if scale < 1.0:
			img.resize(maxi(1, int(img.get_width() * scale)), maxi(1, int(img.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
		img.save_jpg(dir.path_join("screenshot.jpg"), SCREENSHOT_QUALITY)
	set_state(report["id"], {"state": "queued"})
	return report["id"]


## The saved report, or {} if there is none.
func load_report(id: String) -> Dictionary:
	var path := _dir(id).path_join("report.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## The screenshot's path, or "" when the report has none.
func screenshot_path(id: String) -> String:
	var path := _dir(id).path_join("screenshot.jpg")
	return path if FileAccess.file_exists(path) else ""


## The report's folder as an OS path, for revealing it on desktop.
func folder_path(id: String) -> String:
	return ProjectSettings.globalize_path(_dir(id))


## {"state": "queued" | "sent" | "failed", "issue_url", "error", "retry_at", "sent_at"}.
func state_of(id: String) -> Dictionary:
	var path := _dir(id).path_join("state.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Replaces the report's state.
func set_state(id: String, state: Dictionary) -> void:
	_write(_dir(id).path_join("state.json"), JSON.stringify(state, "  ", true))


## Every saved report, newest first: {"id", "title", "created_at", "state", "issue_url"}.
func list() -> Array:
	var out := []
	var root := ProjectSettings.globalize_path(base)
	if not DirAccess.dir_exists_absolute(root):
		return out
	for id in DirAccess.get_directories_at(root):
		var report := load_report(id)
		if report.is_empty():
			continue
		var st := state_of(id)
		out.append({"id": id, "title": report.get("title", ""), "created_at": report.get("created_at", ""), "state": st.get("state", "queued"), "issue_url": st.get("issue_url", "")})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] > b["id"])
	return out


## Ids still waiting to be sent whose retry time has passed, oldest first.
func due(now_unix: float = Time.get_unix_time_from_system()) -> Array:
	var out := []
	for row in list():
		if row["state"] == "sent":
			continue
		if float(state_of(row["id"]).get("retry_at", 0.0)) <= now_unix:
			out.append(row["id"])
	out.reverse()
	return out


## Deletes a report and its files.
func delete(id: String) -> void:
	var dir := ProjectSettings.globalize_path(_dir(id))
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


## Deletes sent reports older than KEEP_SENT_DAYS. Returns how many went.
func prune(now_unix: float = Time.get_unix_time_from_system()) -> int:
	var removed := 0
	for row in list():
		var st := state_of(row["id"])
		if st.get("state", "") == "sent" and now_unix - float(st.get("sent_at", now_unix)) > KEEP_SENT_DAYS * 86400.0:
			delete(row["id"])
			removed += 1
	return removed


## GitHub's prefilled new-issue page for filing a report by hand in the browser. The body is a
## short form of the report (the relay renders the full one); it is cut to keep the URL short
## enough for browsers, and points at the saved folder for the screenshot and full log.
static func handoff_url(repo: String, report: Dictionary) -> String:
	var d: Dictionary = report.get("diagnostics", {})
	var place: Dictionary = d.get("place", {})
	var build: Dictionary = d.get("build", {})
	var machine: Dictionary = d.get("machine", {})
	var lines := PackedStringArray([
		"**Area:** %s · **Severity:** %s" % [label_of(AREAS, report["area"]), label_of(SEVERITIES, report["severity"])],
		"**Place:** x %.1f, z %.1f (%s, edge %s, junction %s)" % [float(place.get("x", 0)), float(place.get("z", 0)), place.get("road", ""), place.get("edge_id", ""), place.get("node_id", "")],
		"",
		"_Attach screenshot.jpg from the report folder here._",
		"",
		"| | |", "|---|---|",
		"| Build | %s (%s) |" % [build.get("commit", ""), ", ".join(_present([build.get("branch", ""), build.get("date", ""), "dirty" if build.get("dirty", false) else ""]))],
		"| Machine | %s %s, %s, %s |" % [machine.get("os", ""), machine.get("os_version", ""), machine.get("cpu", ""), machine.get("gpu", "")],
		"| Settings | preset %s, tone %s |" % [d.get("settings", {}).get("preset", ""), d.get("settings", {}).get("tone_mode", "")],
		"| Frame time | avg %s ms, p99 %s ms |" % [d.get("frame_time", {}).get("avg_ms", 0), d.get("frame_time", {}).get("p99_ms", 0)],
		"",
		"Report id `%s`; full diagnostics and log in the saved report.json." % report["id"],
	])
	var description := str(report.get("description", ""))
	if description != "":
		lines.insert(3, description)
		lines.insert(4, "")
	var tag_ids: Array = report.get("tags", [])
	if not tag_ids.is_empty():
		lines.insert(1, "**Tags:** " + ", ".join(tag_labels(tag_ids)))
	var labels := "in-game-report,needs-triage,area:%s,severity:%s" % [report["area"], report["severity"]]
	for id: Variant in tag_ids:
		labels += ",tag:%s" % id
	var head := "https://github.com/%s/issues/new?labels=%s&title=%s&body=" % [repo, labels.uri_encode(), str(report["title"]).uri_encode()]
	var body := "\n".join(lines)
	while body.length() > 0 and (head + body.uri_encode()).length() > HANDOFF_URL_MAX:
		body = body.substr(0, body.length() - 200)
	return head + body.uri_encode()


static func _present(parts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for p in parts:
		if str(p) != "":
			out.append(str(p))
	return out


func _dir(id: String) -> String:
	return base.path_join(id)


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
