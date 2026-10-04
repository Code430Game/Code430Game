extends Node
## The vehicles the game knows: the base set (vehicles.v0.json) plus any pack entries merged
## after it (same id replaces). Traffic picks from it by road and hour; the player's car and
## stolen cars build from its entries. Autoload as VehicleCatalogue.
## Schema: docs/pack-format/vehicles.schema.v0.json.

const BASE_PATH := "res://actors/vehicles/vehicles.v0.json"
const BODY_CLASSES := ["sedan", "hatchback", "coupe", "suv", "pickup", "van", "box_truck", "taxi", "bus"]
const FALLBACK_ID := "sedan"
## Road classes (OSM highway values) to the spawn groups entries weight by.
const MOTORWAY_CLASSES := ["motorway", "motorway_link", "trunk", "trunk_link"]
const ARTERIAL_CLASSES := ["primary", "primary_link", "secondary", "secondary_link", "tertiary", "tertiary_link"]

var default_player: String = FALLBACK_ID
var _entries: Dictionary = {}  # id -> entry
var _order: PackedStringArray = PackedStringArray()  # ids in load order (stable class indices)


func _ready() -> void:
	if _entries.is_empty():
		load_base()


## (Re)loads the base set, dropping any merged pack entries.
func load_base(path: String = BASE_PATH) -> void:
	_entries.clear()
	_order.clear()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("VehicleCatalogue: cannot read %s" % path)
		return
	default_player = str((data as Dictionary).get("default_player", FALLBACK_ID))
	merge(data)


## Merges a parsed vehicles.v0.json (base or pack). Entries with an unknown body class are
## skipped with a warning. Returns how many entries were added or replaced.
func merge(data: Dictionary) -> int:
	var n := 0
	for e: Variant in data.get("vehicles", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = e
		var id := str(entry.get("id", ""))
		if id == "" or not BODY_CLASSES.has(str(entry.get("body_class", ""))):
			push_warning("VehicleCatalogue: skipping '%s' (unknown body class '%s')" % [id, entry.get("body_class", "")])
			continue
		if not _entries.has(id):
			_order.append(id)
		_entries[id] = entry
		n += 1
	return n


## Merges the vehicles.v0.json in a pack folder, if it has one. Returns the count merged.
func merge_pack_dir(dir: String) -> int:
	var path := dir.path_join("vehicles.v0.json")
	if not FileAccess.file_exists(path):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return merge(data) if typeof(data) == TYPE_DICTIONARY else 0


func ids() -> PackedStringArray:
	return _order


func has(id: String) -> bool:
	return _entries.has(id)


## The entry for `id`, or the fallback sedan's when unknown.
func entry(id: String) -> Dictionary:
	return _entries.get(id, _entries.get(FALLBACK_ID, {}))


## Stable index of an id (for snapshots), or -1.
func index_of(id: String) -> int:
	return _order.find(id)


## Id at a snapshot index, or the fallback when out of range.
func id_at(index: int) -> String:
	return _order[index] if index >= 0 and index < _order.size() else FALLBACK_ID


static func road_group(road_class: String) -> String:
	if MOTORWAY_CLASSES.has(road_class):
		return "motorway"
	if ARTERIAL_CLASSES.has(road_class):
		return "arterial"
	return "local"


## An entry's spawn weight on a road class at an hour (0..24).
static func spawn_weight(e: Dictionary, road_class: String, hour: float) -> float:
	var spawn: Dictionary = e.get("spawn", {})
	var w := float(spawn.get("weight", 0.0))
	w *= float((spawn.get("roads", {}) as Dictionary).get(road_group(road_class), 1.0))
	for span: Variant in spawn.get("hours", []):
		var s: Array = span
		var from := float(s[0])
		var to := float(s[1])
		var inside := (hour >= from and hour < to) if from <= to else (hour >= from or hour < to)
		if inside:
			w *= float(s[2])
	return w


## Picks an entry id for a car spawning on `road_class` at `hour`, weighted. `exclude_bus`
## leaves buses out (roads they don't run on). Returns the fallback when nothing has weight.
func pick_for_spawn(road_class: String, hour: float, rng: RandomNumberGenerator, exclude_bus: bool = false) -> String:
	var total := 0.0
	var weights := PackedFloat32Array()
	for id in _order:
		var e: Dictionary = _entries[id]
		var w := 0.0 if exclude_bus and e.get("body_class") == "bus" else spawn_weight(e, road_class, hour)
		weights.append(w)
		total += w
	if total <= 0.0:
		return FALLBACK_ID
	var r := rng.randf() * total
	for i in range(_order.size()):
		r -= weights[i]
		if r <= 0.0 and weights[i] > 0.0:
			return _order[i]
	return _order[_order.size() - 1]


## A colour from the entry's palette (or its livery's, when the livery overrides it).
func pick_color(id: String, rng: RandomNumberGenerator) -> Color:
	var palette: Array = livery(id).get("colors", entry(id).get("colors", [[1, 1, 1]]))
	var c: Array = palette[rng.randi_range(0, palette.size() - 1)]
	return Color(float(c[0]), float(c[1]), float(c[2]))


## The livery variant for the current tone mode ({} without liveries or when hidden).
func livery(id: String) -> Dictionary:
	var e := entry(id)
	if not e.has("liveries"):
		return {}
	var item: Dictionary = (e["liveries"] as Dictionary).duplicate()
	item["id"] = id
	var tree := Engine.get_main_loop() as SceneTree
	var cm: Node = tree.root.get_node_or_null("ContentMode") if tree != null else null
	return cm.pick_variant(item) if cm != null else (item.get("variants", {}) as Dictionary).get("fallback", {})
