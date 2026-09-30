class_name PackLocator
extends RefCounted
## Finds pack folders on disk. Packs live outside the Godot project (data-only,
## never inside res://): next to the executable, in user://packs, or, when
## running from the editor or a dev checkout, in <repo>/packs.


## Candidate directories that may contain pack folders, most specific first.
static func search_dirs() -> PackedStringArray:
	var dirs := PackedStringArray()
	dirs.append(ProjectSettings.globalize_path("user://packs"))
	dirs.append(OS.get_executable_path().get_base_dir().path_join("packs"))
	if OS.has_feature("editor"):
		dirs.append(ProjectSettings.globalize_path("res://").path_join("../packs").simplify_path())
	return dirs


## Absolute path of the folder holding pack.json for the given pack id, or "".
static func find_pack(pack_id: String) -> String:
	for dir in search_dirs():
		var da := DirAccess.open(dir)
		if da == null:
			continue
		da.list_dir_begin()
		var name := da.get_next()
		while name != "":
			if da.current_is_dir() and not name.begins_with("."):
				var manifest := dir.path_join(name).path_join("pack.json")
				if FileAccess.file_exists(manifest):
					var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
					if typeof(parsed) == TYPE_DICTIONARY and parsed.get("id", "") == pack_id:
						da.list_dir_end()
						return dir.path_join(name)
			name = da.get_next()
		da.list_dir_end()
	return ""
