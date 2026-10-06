extends Node
## ContentMode autoload: the active tone mode and what it allows. Modes are data in
## core/content/modes/*.json; descriptors and levels in content-descriptors.v0.json.
## Gameplay asks `allows(descriptor, level)`, `flag(name)` and `pick_variant(item)`; it never
## compares mode ids. In co-op the host's mode is the session's (`locked` on clients).

signal mode_changed(id: String)

const MODES_DIR := "res://core/content/modes"
const DESCRIPTORS_PATH := "res://core/content/content-descriptors.v0.json"
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"
const SECTION := "content"
const KEY_MODE := "mode"
const DEFAULT_MODE := "gritty"
const ORDER: PackedStringArray = ["clean", "gritty", "dystopia"]

var settings_path: String = DEFAULT_SETTINGS_PATH
var modes: Dictionary = {}  # id -> mode dictionary
var descriptors: Dictionary = {}  # name -> {"about", "aliases"}
var levels: PackedStringArray = ["none", "mild", "strong"]
var current: String = DEFAULT_MODE
## True on a co-op client: the host chose the mode and the menu cannot change it.
var locked: bool = false
var _hidden_warned: Dictionary = {}


func _ready() -> void:
	load_data()
	load_saved()


func load_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DESCRIPTORS_PATH))
	if parsed is Dictionary:
		descriptors = parsed.get("descriptors", {})
		levels = PackedStringArray(parsed.get("levels", levels))
	modes.clear()
	for file in DirAccess.get_files_at(MODES_DIR):
		if not file.ends_with(".json"):
			continue
		var mode: Variant = JSON.parse_string(FileAccess.get_file_as_string(MODES_DIR.path_join(file)))
		if mode is Dictionary and mode.has("id"):
			modes[mode["id"]] = mode


## Mode ids in menu order: the base three first, then anything else alphabetically.
func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in ORDER:
		if modes.has(id):
			out.append(id)
	var rest: Array = modes.keys()
	rest.sort()
	for id: String in rest:
		if not out.has(id):
			out.append(id)
	return out


func mode() -> Dictionary:
	return modes.get(current, {})


func mode_name(id: String = current) -> String:
	return str(modes.get(id, {}).get("name", id))


## Numeric level of `value` for `descriptor` (aliases resolved), or -1 when unknown.
func level_of(descriptor: String, value: String) -> int:
	var aliases: Dictionary = descriptors.get(descriptor, {}).get("aliases", {})
	var resolved: String = str(aliases.get(value, value))
	return levels.find(resolved)


## Whether the active mode allows `descriptor` at `level` (default: the strongest).
func allows(descriptor: String, level: String = "strong") -> bool:
	if not descriptors.has(descriptor):
		return false
	var want := level_of(descriptor, level)
	var max_level := level_of(descriptor, str(mode().get("max", {}).get(descriptor, "none")))
	return want >= 0 and max_level >= 0 and want <= max_level


## Whether every declared descriptor level is allowed.
func allows_descriptors(declared: Dictionary) -> bool:
	for name: String in declared:
		if not allows(name, str(declared[name])):
			return false
	return true


## A mechanic flag of the active mode (violence, lethal_weapons, drug_use, sex_work_services).
func flag(name: String) -> bool:
	return bool(mode().get("flags", {}).get(name, false))


## The active mode's HUD accent colour (`hud.accent`), white when the mode has none.
func hud_accent() -> Color:
	var hex := str(mode().get("hud", {}).get("accent", ""))
	return Color.html(hex) if Color.html_is_valid(hex) else Color.WHITE


## The variant of `item` to show: the active mode's when present and allowed, else the
## fallback when allowed, else {} (hidden; warned once per item id).
func pick_variant(item: Dictionary) -> Dictionary:
	var variants: Dictionary = item.get("variants", {})
	var key: String = str(mode().get("variant_key", current))
	for candidate: String in [key, "fallback"]:
		if variants.has(candidate):
			var v: Dictionary = variants[candidate]
			if allows_descriptors(v.get("descriptors", {})):
				return v
	var id: String = str(item.get("id", "?"))
	if not _hidden_warned.has(id):
		_hidden_warned[id] = true
		print("content: '%s' has nothing allowed in mode '%s', hidden" % [id, current])
	return {}


## Switches mode. Returns false for an unknown id. Persists unless `persist` is false.
func set_mode(id: String, persist: bool = true) -> bool:
	if not modes.has(id):
		push_warning("ContentMode: unknown mode '%s'" % id)
		return false
	var changed := id != current
	current = id
	_hidden_warned.clear()
	if persist:
		save()
	if changed:
		mode_changed.emit(id)
	return true


## Steps through the modes in menu order.
func cycle(delta: int) -> void:
	var all := ids()
	if all.is_empty():
		return
	var i := all.find(current)
	set_mode(all[posmod(i + delta, all.size())])


func load_saved() -> void:
	var cfg := ConfigFile.new()
	var id := DEFAULT_MODE
	if cfg.load(settings_path) == OK:
		var value: Variant = cfg.get_value(SECTION, KEY_MODE, DEFAULT_MODE)
		if typeof(value) == TYPE_STRING and modes.has(value):
			id = value
	set_mode(id, false)


func save() -> Error:
	var dir := settings_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value(SECTION, KEY_MODE, current)
	return cfg.save(settings_path)
