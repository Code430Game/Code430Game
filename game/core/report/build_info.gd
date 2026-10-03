class_name BuildInfo
extends RefCounted
## Which build is running, for issue reports. Exports carry `res://build_info.json`, written by
## `scripts/stamp-build.sh`; a run from source falls back to `dev` and asks git for the commit.

const DEFAULT_PATH := "res://build_info.json"


## The build dictionary: commit, branch, date, dirty, source ("export" or "dev").
static func read(path: String = DEFAULT_PATH, allow_git: bool = true) -> Dictionary:
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and (parsed as Dictionary).has("commit"):
			var d: Dictionary = parsed
			return {
				"commit": str(d.get("commit", "")), "branch": str(d.get("branch", "")),
				"date": str(d.get("date", "")), "dirty": bool(d.get("dirty", false)), "source": "export",
			}
	var info := {"commit": "unknown", "branch": "", "date": "", "dirty": false, "source": "dev"}
	# Exported games never shell out; from source the project sits inside the git checkout.
	if allow_git and not OS.has_feature("template"):
		var root := ProjectSettings.globalize_path("res://")
		var commit := _git(root, ["rev-parse", "--short=12", "HEAD"])
		if commit != "":
			info["commit"] = commit
			info["branch"] = _git(root, ["rev-parse", "--abbrev-ref", "HEAD"])
			info["dirty"] = _git(root, ["status", "--porcelain", "--untracked-files=no"]) != ""
	return info


static func _git(root: String, args: Array) -> String:
	var out: Array = []
	var code := OS.execute("git", PackedStringArray(["-C", root] + args), out, true)
	if code != 0 or out.is_empty():
		return ""
	return str(out[0]).strip_edges()
