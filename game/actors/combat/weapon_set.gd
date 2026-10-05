class_name WeaponSet
extends RefCounted
## The player's weapons (add-weapons-and-combat): the definitions from weapons.v0.json, the
## variant the active tone allows for each, which slot is in hand (0 = empty hands) and the
## rounds left in each magazine. A variant marked lethal is refused when the mode's
## `lethal_weapons` flag is off, whatever its descriptors say.

const WEAPONS_PATH := "res://actors/combat/weapons.v0.json"
const CONFIG_PATH := "res://actors/combat/combat_config.json"

var defs: Array[Dictionary] = []
var config: Dictionary = {}
var slot: int = 0  # 0 = empty hands, then each weapon in file order
var ammo: Dictionary = {}  # weapon id -> rounds in the magazine


func _init(weapons_path: String = WEAPONS_PATH, config_path: String = CONFIG_PATH) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(weapons_path))
	if data is Dictionary:
		for w: Dictionary in data.get("weapons", []):
			defs.append(w)
	defs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	config = cfg if cfg is Dictionary else {}
	refill()


## The weapon `def` as the active tone has it: the definition with its variant's overrides on
## top, or {} when no variant is allowed.
static func resolve(def: Dictionary) -> Dictionary:
	var v: Dictionary = ContentMode.pick_variant(def)
	if v.is_empty() or (bool(v.get("lethal", false)) and not ContentMode.flag("lethal_weapons")):
		return {}
	var out := def.duplicate()
	out.erase("variants")
	for k: String in v:
		out[k] = v[k]
	return out


## What is in hand now, resolved for the tone; {} for empty hands.
func current() -> Dictionary:
	if slot <= 0 or slot > defs.size():
		return {}
	return resolve(defs[slot - 1])


## Next slot round the cycle, skipping weapons the tone leaves empty.
func cycle() -> void:
	for i in range(defs.size() + 1):
		slot = (slot + 1) % (defs.size() + 1)
		if slot == 0 or not current().is_empty():
			return


## Full magazines for every weapon (a tone change swaps what they are, so they start full).
func refill() -> void:
	for d in defs:
		var w := resolve(d)
		ammo[str(d["id"])] = int(w.get("magazine", 0))


func rounds() -> int:
	var w := current()
	return int(ammo.get(str(w.get("id", "")), 0))


func use_round() -> void:
	var w := current()
	var id := str(w.get("id", ""))
	ammo[id] = maxi(int(ammo.get(id, 0)) - 1, 0)


func reload() -> void:
	var w := current()
	ammo[str(w.get("id", ""))] = int(w.get("magazine", 0))


func impact(kind: String) -> Dictionary:
	return (config.get("impacts", {}) as Dictionary).get(kind, {})
