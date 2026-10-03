class_name ReportConfig
extends RefCounted
## Reads `report_config.json`: the relay URL (empty until the relay is deployed) and the repo.

const PATH := "res://core/report/report_config.json"


## {"relay_url": String, "repo": String}.
static func read(path: String = PATH) -> Dictionary:
	var out := {"relay_url": "", "repo": ""}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			out["relay_url"] = str((parsed as Dictionary).get("relay_url", "")).strip_edges()
			out["repo"] = str((parsed as Dictionary).get("repo", "")).strip_edges()
	return out
