extends Node
## PackLoader autoload (add-pack-loader): finds every pack folder in the search directories,
## checks each manifest and its files, resolves dependencies, keeps the enabled set in
## `user://packs.cfg`, and serves the enabled packs' content through one registry.
##
## Approach: discovery walks `PackLocator.search_dirs()` (most specific first) and keeps the
## first folder per pack id, logging the others as shadowed. A pack is loadable when its
## manifest passes the hand-written checks for its schema version, a data-only pack holds only
## allowed file types, it is not a system pack (code is not supported yet) and every dependency
## is present in range. Map packs are never toggled here: the scene names the active map and
## the other maps stay available. `items(type)` reads the content files the enabled packs index
## (v1 `content[]`, or the known v0 file names), tags each item with its pack and drops the ones
## the active tone mode disallows; the cache clears on `mode_changed` and on reload. Every path a
## pack refers to is `pack_id:relative/path`, resolved by `resolve()` inside that pack only.

signal reloaded

const DEFAULT_ENABLED_PATH := "user://packs.cfg"
const SECTION := "packs"
const KEY_ENABLED := "enabled"
const KEY_SEEN := "seen"
const FIRST_PARTY_PREFIX := "code430."
const MANIFEST_NAME := "pack.json"
const KNOWN_SCHEMA_VERSIONS: PackedInt32Array = [0, 1]
const PACK_TYPES: PackedStringArray = ["map", "character", "story", "system"]
const DATA_ONLY_TYPES: PackedStringArray = ["map", "character", "story"]
const ALLOWED_EXTENSIONS: PackedStringArray = [
	"json", "yaml", "yml", "txt", "md", "csv", "gltf", "glb", "bin", "png", "jpg", "jpeg", "ktx2", "webp", "ogg", "wav",
]
const IGNORED_NAMES: PackedStringArray = [".DS_Store", ".gitkeep"]
## Content types the registry serves: the key of the item list inside the file ("" when the
## file is one item). Mirrors CONTENT_SCHEMAS in tools/pack_tools/validate.py.
const CONTENT_LIST_KEYS := {
	"ads": "ads", "vehicles": "vehicles", "weapons": "weapons", "factions": "factions", "turf": "turfs",
	"lap": "laps", "radio": "stations", "music": "tracks", "palettes": "", "presets": "presets", "missions": "missions",
}
## A v0 manifest has no index: these file names imply their type.
const V0_CONTENT_FILES := {
	"ads.v0.json": "ads", "vehicles.v0.json": "vehicles", "weapons.v0.json": "weapons", "factions.v0.json": "factions",
	"turf.v0.json": "turf", "lap.v0.json": "lap", "radio.v0.json": "radio", "music.v0.json": "music",
}
const ID_PATTERN := "^[a-z0-9]+(\\.[a-z0-9-]+)+$"
const SEMVER_PATTERN := "^(\\d+)\\.(\\d+)\\.(\\d+)(-[0-9A-Za-z.-]+)?$"


## One discovered pack folder and what the loader decided about it.
class PackInfo:
	extends RefCounted
	var id: String = ""
	var name: String = ""
	var version: String = ""
	var type: String = ""
	var dir: String = ""
	var schema_version: int = -1
	var manifest: Dictionary = {}
	var content: Array = []  # [{"type", "path"}]
	var dependencies: Array = []  # [{"id", "version"}]
	var trusted: bool = false
	var enabled: bool = true  # the player's choice (map packs: always true)
	var valid: bool = false  # manifest and files pass
	var reason: String = ""  # why it is not loaded, "" when it is
	var shadowed: PackedStringArray = []  # other folders with the same id, ignored
	var announced: bool = false  # found for the first time this start

	func is_map() -> bool:
		return type == "map"

	func is_first_party() -> bool:
		return id.begins_with(FIRST_PARTY_PREFIX)


var enabled_path: String = DEFAULT_ENABLED_PATH
## Directories to scan; empty means `PackLocator.search_dirs()`. Tests point this at fixtures.
var search_dirs: PackedStringArray = PackedStringArray()
## Every discovered pack by id, including the refused ones (the Packs list shows them all).
var packs: Dictionary = {}
## Ids of the packs whose content is served, in dependency order: the active map first.
var loaded_ids: PackedStringArray = PackedStringArray()
## Id of the map pack in play, named by the scene; "" before a map is chosen.
var active_map: String = ""
## The active map's neighbouring districts, loaded with it (district_ids; add-district-stitching).
var active_districts: PackedStringArray = PackedStringArray()
## `--packs=`: the enabled set for this run only, never saved.
var pinned: PackedStringArray = PackedStringArray()
var _pinned: bool = false
var _enabled: PackedStringArray = PackedStringArray()
var _seen: PackedStringArray = PackedStringArray()
var _items_cache: Dictionary = {}  # type -> Array[Dictionary]
var _hash_cache: Dictionary = {}  # dir -> hash
var _id_regex := RegEx.new()
var _semver_regex := RegEx.new()


func _ready() -> void:
	_id_regex.compile(ID_PATTERN)
	_semver_regex.compile(SEMVER_PATTERN)
	if not ContentMode.mode_changed.is_connected(_on_mode_changed):
		ContentMode.mode_changed.connect(_on_mode_changed)
	reload()


func _on_mode_changed(_id: String) -> void:
	clear_cache()


## Scans the search directories again, reads the enabled set and resolves what loads.
func reload() -> void:
	if _id_regex.get_pattern() == "":
		_id_regex.compile(ID_PATTERN)
		_semver_regex.compile(SEMVER_PATTERN)
	packs.clear()
	_hash_cache.clear()
	clear_cache()
	_discover()
	_read_enabled()
	_resolve()
	CharacterProfile.refresh_palettes()
	reloaded.emit()


## The directories scanned, most specific first.
func dirs() -> PackedStringArray:
	return search_dirs if not search_dirs.is_empty() else PackLocator.search_dirs()


## Names the map pack in play; its content leads the registry and the co-op summary.
func set_active_map(id: String) -> void:
	if active_map == id:
		return
	active_map = id
	_resolve()
	clear_cache()
	CharacterProfile.refresh_palettes()


## `--packs=id,id`: the enabled set for this run only.
func pin(ids: PackedStringArray) -> void:
	pinned = ids
	_pinned = true
	reload()


func clear_cache() -> void:
	_items_cache.clear()


# --- discovery ---

func _discover() -> void:
	for dir in dirs():
		var da := DirAccess.open(dir)
		if da == null:
			continue
		da.list_dir_begin()
		var name := da.get_next()
		while name != "":
			if da.current_is_dir() and not name.begins_with("."):
				var folder := dir.path_join(name)
				if FileAccess.file_exists(folder.path_join(MANIFEST_NAME)):
					_take(folder)
			name = da.get_next()
		da.list_dir_end()


## Reads and checks one pack folder; the first folder per id wins, later ones are shadowed.
func _take(folder: String) -> void:
	var info := PackInfo.new()
	info.dir = folder
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(MANIFEST_NAME)))
	if typeof(parsed) != TYPE_DICTIONARY:
		info.id = "folder:" + folder.get_file()
		info.name = folder.get_file()
		info.reason = "pack.json is not valid JSON"
		push_warning("PackLoader: %s: %s" % [folder, info.reason])
		packs[info.id] = info
		return
	info.manifest = parsed
	info.id = str(parsed.get("id", ""))
	info.name = str(parsed.get("name", info.id))
	info.version = str(parsed.get("version", ""))
	info.type = str(parsed.get("type", ""))
	info.trusted = bool(parsed.get("trusted", false))
	var sv: Variant = parsed.get("schema_version", -1)
	info.schema_version = int(sv) if sv is float or sv is int else -1
	if info.id == "" or _id_regex.search(info.id) == null:
		info.id = "folder:" + folder.get_file()
	if packs.has(info.id):
		var first: PackInfo = packs[info.id]
		first.shadowed.append(folder)
		print("packs: %s at %s is shadowed by %s" % [info.id, folder, first.dir])
		return
	info.reason = check_manifest(parsed, folder)
	if info.reason == "" and DATA_ONLY_TYPES.has(info.type):
		info.reason = check_files(folder, info.type)
	if info.reason == "" and info.type == "system":
		info.reason = "runs code: system packs are not supported yet"
	info.valid = info.reason == ""
	info.content = content_index(parsed, folder)
	for d: Variant in parsed.get("dependencies", []):
		if d is Dictionary:
			info.dependencies.append({"id": str(d.get("id", "")), "version": str(d.get("version", "*"))})
	if not info.valid:
		push_warning("PackLoader: %s (%s): %s" % [info.id, folder, info.reason])
	packs[info.id] = info


## The manifest checks the game does itself (the full schema check is the validator's job in
## CI): "" when the manifest is usable, else what is wrong with it.
func check_manifest(m: Dictionary, folder: String) -> String:
	var sv: Variant = m.get("schema_version", null)
	if not (sv is float or sv is int) or not KNOWN_SCHEMA_VERSIONS.has(int(sv)):
		return "%s: unknown schema_version %s (known: 0, 1)" % [folder.get_file(), str(sv)]
	for key: String in ["id", "name", "version", "type", "engine_api", "license", "attribution"]:
		if not m.has(key):
			return "pack.json is missing '%s'" % key
	if _id_regex.search(str(m["id"])) == null:
		return "id '%s' is not a valid pack id" % str(m["id"])
	if _semver_regex.search(str(m["version"])) == null:
		return "version '%s' is not a semantic version" % str(m["version"])
	if not PACK_TYPES.has(str(m["type"])):
		return "type '%s' is not map, character, story or system" % str(m["type"])
	if str(m["type"]) == "system" and not bool(m.get("trusted", false)):
		return "system packs must be marked trusted"
	if str(m["type"]) != "system" and bool(m.get("trusted", false)):
		return "a data-only pack may not be marked trusted"
	if str(m["type"]) == "map" and not (m.get("map") is Dictionary):
		return "map packs need a 'map' section"
	if int(sv) == 1:
		for key: String in ["supported_modes", "max_descriptors"]:
			if not m.has(key):
				return "a v1 pack.json needs '%s'" % key
		if str(m["type"]) == "character" and not (m.get("character") is Dictionary):
			return "character packs need a 'character' section"
		if str(m["type"]) == "story" and not (m.get("story") is Dictionary):
			return "story packs need a 'story' section"
		for entry: Variant in m.get("content", []):
			if not (entry is Dictionary) or not CONTENT_LIST_KEYS.has(str(entry.get("type", ""))):
				return "content[] has an entry with an unknown type"
			if not _inside(str(entry.get("path", ""))):
				return "content path '%s' leaves the pack folder" % str(entry.get("path", ""))
	return ""


## "" when every file in a data-only pack has an allowed type, else the first offender.
func check_files(folder: String, pack_type: String) -> String:
	if not DATA_ONLY_TYPES.has(pack_type):
		return ""
	var files: Array[String] = []
	_collect_files(folder, "", files)
	files.sort()
	for rel in files:
		if IGNORED_NAMES.has(rel.get_file()):
			continue
		var ext := rel.get_extension().to_lower()
		if not ALLOWED_EXTENSIONS.has(ext):
			return "file %s is not allowed in a %s pack" % [rel, pack_type]
	return ""


## The pack's content entries: `content[]` for v1, or the known v0 file names present.
static func content_index(m: Dictionary, folder: String) -> Array:
	var out: Array = []
	if int(m.get("schema_version", 0)) == 1:
		for entry: Variant in m.get("content", []):
			if entry is Dictionary:
				out.append({"type": str(entry.get("type", "")), "path": str(entry.get("path", ""))})
		return out
	for name: String in V0_CONTENT_FILES:
		if FileAccess.file_exists(folder.path_join(name)):
			out.append({"type": V0_CONTENT_FILES[name], "path": name})
	return out


# --- enabled set ---

func _read_enabled() -> void:
	_enabled.clear()
	_seen.clear()
	var cfg := ConfigFile.new()
	var had_file := cfg.load(enabled_path) == OK
	var enabled: Variant = cfg.get_value(SECTION, KEY_ENABLED, PackedStringArray())
	var seen: Variant = cfg.get_value(SECTION, KEY_SEEN, PackedStringArray())
	if enabled is PackedStringArray or enabled is Array:
		_enabled = PackedStringArray(enabled)
	if seen is PackedStringArray or seen is Array:
		_seen = PackedStringArray(seen)
	var changed := false
	for id: String in packs:
		var info: PackInfo = packs[id]
		if _pinned:
			info.enabled = info.is_map() or pinned.has(id)
			continue
		if not _seen.has(id):
			# New here: enabled, announced once, remembered.
			_seen.append(id)
			if not _enabled.has(id):
				_enabled.append(id)
			info.announced = true
			changed = true
			if had_file or not info.is_first_party():
				print("packs: found %s %s (%s), enabled" % [info.name, info.version, id])
		info.enabled = info.is_map() or _enabled.has(id)
	if changed and not _pinned:
		_save_enabled()


func _save_enabled() -> void:
	var dir := enabled_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var cfg := ConfigFile.new()
	cfg.load(enabled_path)
	cfg.set_value(SECTION, KEY_ENABLED, _enabled)
	cfg.set_value(SECTION, KEY_SEEN, _seen)
	cfg.save(enabled_path)


func is_enabled(id: String) -> bool:
	return packs.has(id) and (packs[id] as PackInfo).enabled


## Enables or disables a non-map pack and saves the choice; takes effect at the next reload.
## Returns false for unknown ids, map packs and system packs.
func set_enabled(id: String, on: bool) -> bool:
	if not packs.has(id):
		return false
	var info: PackInfo = packs[id]
	if info.is_map() or info.type == "system":
		return false
	info.enabled = on
	if on and not _enabled.has(id):
		_enabled.append(id)
	elif not on:
		var i := _enabled.find(id)
		if i >= 0:
			_enabled.remove_at(i)
	if not _pinned:
		_save_enabled()
	return true


## Ids of the packs the player has enabled (map packs included), sorted.
func enabled_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in packs:
		if (packs[id] as PackInfo).enabled:
			out.append(id)
	out.sort()
	return out


# --- resolution ---

## Decides `loaded_ids`: the active map, then every enabled, valid, dependency-satisfied
## non-map pack in dependency order (ties by id). Disabled packs get a readable reason.
func _resolve() -> void:
	loaded_ids.clear()
	active_districts = district_ids(active_map) if active_map != "" else PackedStringArray()
	var candidates: Array[String] = []
	for id: String in packs:
		var info: PackInfo = packs[id]
		if info.valid and info.reason == "":
			pass
		elif info.valid:
			info.reason = ""  # a reason from an earlier resolve
		if not info.valid:
			continue
		if info.is_map():
			if id == active_map or id in active_districts:
				candidates.append(id)
			continue
		if not info.enabled:
			continue
		var story: Variant = info.manifest.get("story", null)
		if story is Dictionary and active_map != "" and str(story.get("map", "")) != "" and str(story.get("map", "")) != active_map and not (str(story.get("map", "")) in active_districts):
			info.reason = "placed on %s, not the map in play" % str(story.get("map", ""))
			continue
		candidates.append(id)
	# Dependencies: present (any discovered pack, map packs included) and in range.
	var ok: Array[String] = []
	for id in candidates:
		var info: PackInfo = packs[id]
		var missing := ""
		for dep: Dictionary in info.dependencies:
			var dep_id := str(dep["id"])
			var spec := str(dep["version"])
			if not packs.has(dep_id) or not (packs[dep_id] as PackInfo).valid:
				missing = "needs %s %s, which is not installed" % [dep_id, spec]
				break
			var have := (packs[dep_id] as PackInfo).version
			if not semver_satisfies(have, spec):
				missing = "needs %s %s, found %s" % [dep_id, spec, have]
				break
		if missing != "":
			info.reason = missing
			print("packs: %s disabled: %s" % [id, missing])
		else:
			ok.append(id)
	# Kahn's algorithm, smallest id first, so the order (and the pack set hash) is deterministic.
	var remaining: Array[String] = ok.duplicate()
	remaining.sort()
	var placed: Dictionary = {}
	while not remaining.is_empty():
		var progressed := false
		for id in remaining.duplicate():
			var deps_done := true
			for dep: Dictionary in (packs[id] as PackInfo).dependencies:
				var dep_id := str(dep["id"])
				if ok.has(dep_id) and not placed.has(dep_id):
					deps_done = false
					break
			if deps_done:
				loaded_ids.append(id)
				placed[id] = true
				remaining.erase(id)
				progressed = true
				break
		if not progressed:
			for id in remaining:
				(packs[id] as PackInfo).reason = "dependency cycle"
				print("packs: %s disabled: dependency cycle" % id)
			break
	if active_map != "" and loaded_ids.has(active_map):
		loaded_ids.erase(active_map)
		loaded_ids.insert(0, active_map)


## `version` satisfies `spec`: exact, `^1.2`, `~1.2.3`, `>=1.0 <2.0` (space separated
## comparators) or `*`. Mirrors semver_satisfies in tools/pack_tools/validate.py.
static func semver_satisfies(version: String, spec: String) -> bool:
	var v := _triple(version)
	if v.is_empty():
		return false
	var s := spec.strip_edges()
	if s == "" or s == "*":
		return true
	for part in s.split(" ", false):
		if not _satisfies_one(v, part):
			return false
	return true


static func _triple(text: String) -> PackedInt32Array:
	var core := text.get_slice("-", 0)
	var parts := core.split(".")
	if parts.size() != 3:
		return PackedInt32Array()
	var out := PackedInt32Array()
	for p in parts:
		if not p.is_valid_int():
			return PackedInt32Array()
		out.append(int(p))
	return out


static func _pad(text: String) -> Array:
	var parts := text.split(".")
	var nums := PackedInt32Array()
	for i in range(mini(3, parts.size())):
		nums.append(int(parts[i]) if parts[i].is_valid_int() else 0)
	while nums.size() < 3:
		nums.append(0)
	return [nums, parts.size()]


static func _cmp(a: PackedInt32Array, b: PackedInt32Array) -> int:
	for i in range(3):
		if a[i] != b[i]:
			return -1 if a[i] < b[i] else 1
	return 0


static func _satisfies_one(v: PackedInt32Array, part: String) -> bool:
	if part.begins_with("^"):
		var low: PackedInt32Array = _pad(part.substr(1))[0]
		var high := PackedInt32Array([low[0] + 1, 0, 0])
		if low[0] == 0 and low[1] > 0:
			high = PackedInt32Array([0, low[1] + 1, 0])
		elif low[0] == 0 and low[1] == 0:
			high = PackedInt32Array([0, 0, low[2] + 1])
		return _cmp(v, low) >= 0 and _cmp(v, high) < 0
	if part.begins_with("~"):
		var padded: Array = _pad(part.substr(1))
		var low: PackedInt32Array = padded[0]
		var high := PackedInt32Array([low[0] + 1, 0, 0]) if int(padded[1]) == 1 else PackedInt32Array([low[0], low[1] + 1, 0])
		return _cmp(v, low) >= 0 and _cmp(v, high) < 0
	for op: String in [">=", "<=", ">", "<", "="]:
		if part.begins_with(op):
			var bound: PackedInt32Array = _pad(part.substr(op.length()))[0]
			var c := _cmp(v, bound)
			match op:
				">=":
					return c >= 0
				"<=":
					return c <= 0
				">":
					return c > 0
				"<":
					return c < 0
			return c == 0
	var padded: Array = _pad(part)
	var exact: PackedInt32Array = padded[0]
	var given: int = padded[1]
	for i in range(mini(3, given)):
		if v[i] != exact[i]:
			return false
	return true


# --- namespaces ---

## Whether `rel` stays inside a pack folder: relative, no `..` segment.
static func _inside(rel: String) -> bool:
	if rel == "" or rel.begins_with("/") or rel.begins_with("\\") or rel.is_absolute_path():
		return false
	for seg in rel.replace("\\", "/").split("/"):
		if seg == "..":
			return false
	return true


## Absolute path of `pack_id:relative/path` inside that pack, or "" (with an error) when the
## pack is not loaded, the path escapes the folder, or the file does not exist.
func resolve(ref: String) -> String:
	var sep := ref.find(":")
	if sep <= 0:
		push_error("PackLoader: '%s' is not pack_id:path" % ref)
		return ""
	var id := ref.substr(0, sep)
	var rel := ref.substr(sep + 1)
	if not packs.has(id) or not loaded_ids.has(id):
		push_error("PackLoader: pack '%s' is not loaded (for %s)" % [id, ref])
		return ""
	if not _inside(rel):
		push_error("PackLoader: '%s' leaves the pack folder of %s" % [rel, id])
		return ""
	var path: String = (packs[id] as PackInfo).dir.path_join(rel)
	if not FileAccess.file_exists(path):
		push_error("PackLoader: %s has no file %s" % [id, rel])
		return ""
	return path


## The folder of a discovered map pack by id, or "" (the scene loads the map from it).
## The neighbouring districts played with map `id` (add-district-stitching): every other
## valid map pack of the same city (same origin and projection, a border on its chunk grid)
## whose border overlaps none already in the set, by id. Found, not listed: installing a
## neighbouring district is enough.
func district_ids(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not packs.has(id) or not (packs[id] as PackInfo).is_map():
		return out
	var set_manifests: Array = [(packs[id] as PackInfo).manifest]
	if not ((set_manifests[0] as Dictionary).get("map", {}) as Dictionary).has("border"):
		return out
	var others: Array = packs.keys()
	others.sort()
	for other: String in others:
		var info: PackInfo = packs[other]
		if other == id or not info.is_map() or not info.valid:
			continue
		var trial := set_manifests.duplicate()
		trial.append(info.manifest)
		if DistrictSet.refusal(trial) == "":
			set_manifests.append(info.manifest)
			out.append(other)
	return out


## The folders of the map in play and its districts, the map first.
func district_dirs(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var first := map_pack_dir(id)
	if first == "":
		return out
	out.append(first)
	for other in district_ids(id):
		out.append(map_pack_dir(other))
	return out


func map_pack_dir(id: String) -> String:
	if not packs.has(id):
		return ""
	var info: PackInfo = packs[id]
	return info.dir if info.is_map() and info.valid else ""


## Ids of every valid map pack, sorted.
func map_pack_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in packs:
		var info: PackInfo = packs[id]
		if info.is_map() and info.valid:
			out.append(id)
	out.sort()
	return out


## The discovered packs for the Packs list: maps first, then by name.
func listed() -> Array[PackInfo]:
	var out: Array[PackInfo] = []
	for id: String in packs:
		out.append(packs[id])
	out.sort_custom(func(a: PackInfo, b: PackInfo) -> bool:
		if a.is_map() != b.is_map():
			return a.is_map()
		return a.name.to_lower() < b.name.to_lower())
	return out


# --- registry ---

## Every item of `type` across the loaded packs, each with `pack_id` and `source`
## (`pack_id:path`), minus the items whose own descriptors the active mode disallows.
## Variant choice stays with ContentMode.pick_variant. Cached per type until the mode changes.
func items(type: String) -> Array[Dictionary]:
	if _items_cache.has(type):
		return _items_cache[type]
	var out: Array[Dictionary] = []
	var list_key: String = str(CONTENT_LIST_KEYS.get(type, type))
	for id in loaded_ids:
		var info: PackInfo = packs[id]
		for entry: Dictionary in info.content:
			if str(entry["type"]) != type:
				continue
			var rel := str(entry["path"])
			var path := info.dir.path_join(rel)
			if not FileAccess.file_exists(path):
				push_warning("PackLoader: %s lists %s but the file is missing" % [id, rel])
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not (parsed is Dictionary):
				push_warning("PackLoader: %s: %s is not a JSON object" % [id, rel])
				continue
			var source := "%s:%s" % [id, rel]
			if list_key == "":
				var one: Dictionary = (parsed as Dictionary).duplicate()
				one["pack_id"] = id
				one["source"] = source
				out.append(one)
				continue
			for raw: Variant in (parsed as Dictionary).get(list_key, []):
				if not (raw is Dictionary):
					continue
				var item: Dictionary = (raw as Dictionary).duplicate()
				if not ContentMode.allows_descriptors(item.get("descriptors", {})):
					continue
				item["pack_id"] = id
				item["source"] = source
				out.append(item)
	_items_cache[type] = out
	return out


# --- co-op summary ---

## SHA-256 over pack.json plus every file's relative path and contents, leaving out the GLB
## chunk cache; two regenerated packs with the same file sizes still differ.
static func content_hash(dir: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(dir.path_join(MANIFEST_NAME)))
	for rel in pack_files(dir):
		var bytes := FileAccess.get_file_as_bytes(dir.path_join(rel))
		ctx.update(("%s:%d\n" % [rel, bytes.size()]).to_utf8_buffer())
		ctx.update(bytes)
	return ctx.finish().hex_encode()


## Every file of a pack folder, relative and sorted, without `chunks/` (generated locally).
static func pack_files(dir: String) -> Array[String]:
	var entries: Array[String] = []
	_collect_files(dir, "", entries)
	entries.sort()
	var out: Array[String] = []
	for rel in entries:
		if not rel.begins_with("chunks/"):
			out.append(rel)
	return out


static func _collect_files(root: String, rel_dir: String, out: Array[String]) -> void:
	var da := DirAccess.open(root.path_join(rel_dir) if rel_dir != "" else root)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name.begins_with("."):
			name = da.get_next()
			continue
		var rel := rel_dir.path_join(name) if rel_dir != "" else name
		if da.current_is_dir():
			_collect_files(root, rel, out)
		else:
			out.append(rel)
		name = da.get_next()
	da.list_dir_end()


## A loaded pack's content hash, computed once per folder and reused.
func cached_hash(id: String) -> String:
	var dir: String = (packs[id] as PackInfo).dir
	if not _hash_cache.has(dir):
		_hash_cache[dir] = content_hash(dir)
	return _hash_cache[dir]


## The enabled pack set for co-op checks: `[{"id", "version", "hash"}]` sorted by id.
func manifest_summary() -> Array:
	var ids: Array[String] = []
	for id in loaded_ids:
		ids.append(id)
	ids.sort()
	var out: Array = []
	for id in ids:
		var info: PackInfo = packs[id]
		out.append({"id": id, "version": info.version, "hash": cached_hash(id)})
	return out


## Readable one-liner for a pack's state in the Packs list.
func state_text(info: PackInfo) -> String:
	if info.type == "system":
		return "runs code: not supported yet"
	if not info.valid:
		return info.reason
	if info.is_map():
		return "active map" if info.id == active_map else "map: A to play it"
	if not info.enabled:
		return "disabled"
	if info.reason != "":
		return info.reason
	return "enabled"
