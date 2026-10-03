class_name Diagnostics
extends RefCounted
## Diagnostics for an issue report (docs/report-format/report.schema.v1.json, "diagnostics").
##
## Build, engine, machine, settings and session are read here. The place and the loaded packs
## come from the scene that knows them (`place_for`, `MapPack.manifest_summary`). Every string is
## passed through `Redactor` before it is stored, so nothing below reaches a file or the network
## with the player's home directory or account name in it.

const LOG_TAIL_LINES := 200
const LOG_LINE_MAX := 500
## A junction node closer than this to the nearest edge's end is named in the place.
const NODE_RADIUS_M := 40.0
const EDGE_RADIUS_M := 40.0


## Strips the home directory and the account name from strings. Generic account names (the
## Steam Deck's `deck`, `root` and the like) identify nobody and are common words in the
## diagnostics ("preset deck"), so only the home directory is replaced for them.
class Redactor:
	extends RefCounted
	const GENERIC_USERS := ["deck", "root", "user", "admin", "steam", "player", "guest"]
	var home: String
	var user: String

	func _init(home_dir: String, user_name: String) -> void:
		home = home_dir.trim_suffix("/").trim_suffix("\\")
		user = "" if user_name.length() < 3 or user_name.to_lower() in GENERIC_USERS else user_name

	## The string with the home directory as ~ and the account name as <user>.
	func redact(s: String) -> String:
		var out := s
		if home.length() > 1:
			out = out.replace(home, "~")
		if user != "":
			var re := RegEx.create_from_string("(?i)\\b" + _escape(user) + "\\b")
			out = re.sub(out, "<user>", true)
		return out

	## Redacts every string inside dictionaries and arrays, recursively.
	func redact_value(v: Variant) -> Variant:
		if v is String:
			return redact(v)
		if v is Dictionary:
			var d := {}
			for k in v:
				d[k] = redact_value(v[k])
			return d
		if v is Array:
			var a := []
			for item in v:
				a.append(redact_value(item))
			return a
		return v

	static func _escape(s: String) -> String:
		var out := ""
		for c in s:
			out += ("\\" + c) if ".^$*+?()[]{}|\\".contains(c) else c
		return out


## The redactor for this machine.
static func local_redactor() -> Redactor:
	var home := OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE")
	var user := OS.get_environment("USER")
	if user == "":
		user = OS.get_environment("USERNAME")
	return Redactor.new(home, user)


## Full diagnostics. `place` comes from `place_for`, `packs` is a list of {"id", "version"}, and
## `frame_time` is a `FrameTimes.stats()` snapshot taken when the report was captured.
static func collect(place: Dictionary, packs: Array, frame_time: Dictionary, redactor: Redactor = null) -> Dictionary:
	var r := redactor if redactor != null else local_redactor()
	var mem: Dictionary = OS.get_memory_info()
	var size := DisplayServer.window_get_size()
	var pack_rows := []
	for p in packs:
		pack_rows.append({"id": str(p.get("id", "")), "version": str(p.get("version", ""))})
	var role := "single"
	var peers := 1
	if Session.is_host():
		role = "host"
		peers = Session.player_count()
	elif Session.is_client():
		role = "client"
		peers = Session.player_count()
	var diag := {
		"build": BuildInfo.read(),
		"engine": {"godot": str(Engine.get_version_info().get("string", ""))},
		"machine": {
			"os": OS.get_name(),
			"distribution": OS.get_distribution_name(),
			"os_version": OS.get_version(),
			"cpu": OS.get_processor_name(),
			"cpu_count": OS.get_processor_count(),
			"gpu": RenderingServer.get_video_adapter_name(),
			"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
			"graphics_api": "%s %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_api_version()],
			"memory_mb": int(int(mem.get("physical", 0)) / (1024 * 1024)),
			"resolution": [size.x, size.y],
			"deck": Settings.is_steam_deck,
		},
		"settings": {"preset": Settings.current_preset_name, "tone_mode": ContentMode.current},
		"packs": pack_rows,
		"session": {"role": role, "peers": peers},
		"place": place if not place.is_empty() else empty_place(),
		"frame_time": frame_time,
	}
	return r.redact_value(diag)


## A place with nothing known, for menus and loading screens.
static func empty_place() -> Dictionary:
	return {"x": 0.0, "y": 0.0, "z": 0.0, "heading_deg": 0.0, "mode": "none", "road": "", "edge_id": "", "node_id": "", "time_of_day": ""}


## Where the player is: position, heading (degrees clockwise from -z), on foot or in a car, the
## nearest road and its edge id, the nearest junction or end node of that edge, and the clock.
static func place_for(graph: RoadGraph, body: Node3D, driving: bool, clock: String) -> Dictionary:
	var place := empty_place()
	if body == null:
		return place
	var p := body.global_position
	var fwd := -body.global_transform.basis.z
	place["x"] = snappedf(p.x, 0.1)
	place["y"] = snappedf(p.y, 0.1)
	place["z"] = snappedf(p.z, 0.1)
	place["heading_deg"] = snappedf(fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0), 0.1)
	place["mode"] = "car" if driving else "foot"
	place["time_of_day"] = clock
	if graph == null:
		return place
	var hit := graph.nearest_edge(p, EDGE_RADIUS_M)
	if hit.is_empty():
		return place
	var e: RoadGraph.RoadEdge = hit["edge"]
	place["road"] = e.name if e.name != "" else e.road_class.replace("_", " ")
	place["edge_id"] = e.id
	var best := ""
	var best_d := NODE_RADIUS_M
	for nid in [e.from_node, e.to_node]:
		var d := Vector2(p.x, p.z).distance_to(Vector2(graph.nodes[nid].position.x, graph.nodes[nid].position.z))
		if d < best_d:
			best_d = d
			best = nid
	place["node_id"] = best
	return place


## The last `max_lines` lines of the game's log file, each cut to LOG_LINE_MAX characters and
## redacted. Empty when file logging is off.
static func log_tail(redactor: Redactor = null, path: String = "", max_lines: int = LOG_TAIL_LINES) -> Array:
	var r := redactor if redactor != null else local_redactor()
	var log_path := path
	if log_path == "":
		log_path = str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	if not FileAccess.file_exists(log_path):
		return []
	var lines := FileAccess.get_file_as_string(log_path).split("\n")
	var out := []
	for i in range(maxi(0, lines.size() - max_lines - 1), lines.size()):
		var line := lines[i].strip_edges(false, true)
		if line == "" and i == lines.size() - 1:
			continue
		out.append(r.redact(line.substr(0, LOG_LINE_MAX)))
	return out.slice(maxi(0, out.size() - max_lines))
