class_name WeaponPage
extends WheelPage
## The wheel's Weapons page (add-weapon-selector): one segment per slot the active tone fills,
## slot 0 first. Fists are not an entry in weapons.v0.json (slot 0 is "nothing in hand"), so
## the page names slot 0 itself.

const FISTS_NAME := "Fists"

var weapons: WeaponSet


func _init(weapon_set: WeaponSet = null) -> void:
	weapons = weapon_set


func title() -> String:
	return "Weapons"


func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if weapons == null:
		return out
	for s in weapons.available():
		out.append(entry(s))
	return out


## The segment for slot `s`: its icon, name and rounds.
func entry(s: int) -> Dictionary:
	var e := {"icon": WeaponIcons.texture(weapons.icon_names(s)), "name": FISTS_NAME, "sub": "", "enabled": true}
	if s > 0:
		var w := WeaponSet.resolve(weapons.defs[s - 1])
		e["name"] = str(w.get("name", ""))
		var mag := int(w.get("magazine", 0))
		if mag > 0:
			e["sub"] = "%d / %d" % [int(weapons.ammo.get(str(w.get("id", "")), 0)), mag]
	return e


func current_index() -> int:
	return weapons.available().find(weapons.slot) if weapons != null else -1


func choose(index: int) -> void:
	var slots := weapons.available()
	if index >= 0 and index < slots.size():
		weapons.pick(slots[index])
