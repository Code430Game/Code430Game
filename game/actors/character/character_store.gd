class_name CharacterStore
extends RefCounted
## Saved characters in one JSON file: the last created body and named presets.
## {"last": profile, "presets": [{"name": String, "profile": profile}, ...]}

const DEFAULT_PATH := "user://characters.json"


static func load_file(path: String = DEFAULT_PATH) -> Dictionary:
	var data := {"last": {}, "presets": []}
	if not FileAccess.file_exists(path):
		return data
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var d: Dictionary = parsed
		if d.get("last") is Dictionary and not (d["last"] as Dictionary).is_empty():
			data["last"] = CharacterProfile.normalise(d["last"])
		if d.get("presets") is Array:
			for item: Variant in d["presets"]:
				if item is Dictionary and item.get("profile") is Dictionary:
					data["presets"].append({"name": str(item.get("name", "preset")), "profile": CharacterProfile.normalise(item["profile"])})
	return data


static func save_file(data: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("CharacterStore: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(data, "  "))
	return true


## The last created character; with none saved, a random one that is saved as last.
static func last_or_random(path: String = DEFAULT_PATH) -> Dictionary:
	var data := load_file(path)
	if not (data["last"] as Dictionary).is_empty():
		return data["last"]
	var p := CharacterProfile.random()
	data["last"] = p
	save_file(data, path)
	return p


static func save_last(profile: Dictionary, path: String = DEFAULT_PATH) -> void:
	var data := load_file(path)
	data["last"] = CharacterProfile.normalise(profile)
	save_file(data, path)


static func presets(path: String = DEFAULT_PATH) -> Array:
	return load_file(path)["presets"]


## Saves `profile` under `name`, replacing a preset of the same name. Empty name: the next free "Character N".
static func save_preset(profile: Dictionary, name: String = "", path: String = DEFAULT_PATH) -> String:
	var data := load_file(path)
	var list: Array = data["presets"]
	if name == "":
		var n := 1
		while _index_of(list, "Character %d" % n) >= 0:
			n += 1
		name = "Character %d" % n
	var entry := {"name": name, "profile": CharacterProfile.normalise(profile)}
	var i := _index_of(list, name)
	if i >= 0:
		list[i] = entry
	else:
		list.append(entry)
	save_file(data, path)
	return name


static func delete_preset(name: String, path: String = DEFAULT_PATH) -> bool:
	var data := load_file(path)
	var list: Array = data["presets"]
	var i := _index_of(list, name)
	if i < 0:
		return false
	list.remove_at(i)
	save_file(data, path)
	return true


static func _index_of(list: Array, name: String) -> int:
	for i in range(list.size()):
		if str((list[i] as Dictionary).get("name", "")) == name:
			return i
	return -1
