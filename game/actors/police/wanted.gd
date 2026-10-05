class_name Wanted
extends Node
## The wanted level (add-police 1.1): 0 to `max_stars`. A crime counts only when someone sees
## it: a walking pedestrian within `witness_m`, or a police unit within `police_sight_m`.
## While police see the player the clock stands still; out of their sight for `lose_s[stars]`
## the level drops a star, and at zero the chase is over.

signal stars_changed(stars: int)

const CONFIG_PATH := "res://actors/police/police_config.json"

var config: Dictionary = {}
var stars: int = 0
var unseen_s: float = 0.0
var peds: PedestrianManager
## Positions of police cars and officers, kept current by the PoliceManager.
var police_positions := PackedVector3Array()
## Who the police are after (the local player's body or car), set by the scene.
var target: Node3D


func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	config = data if data is Dictionary else {}


## True when somebody sees `pos`: a walker in witness range or police in sight range.
func witnessed(pos: Vector3) -> bool:
	if police_sees(pos):
		return true
	if peds != null:
		var r := float(config.get("witness_m", 30.0))
		for a in peds.agents:
			if a.state == Pedestrian.State.WALKING and a.position().distance_to(pos) <= r:
				return true
	return false


func police_sees(pos: Vector3) -> bool:
	var r := float(config.get("police_sight_m", 55.0))
	for p in police_positions:
		if p.distance_to(pos) <= r:
			return true
	return false


## A crime of `kind` (see `crimes` in the config) at `pos`. Returns true when it counted.
func report(kind: String, pos: Vector3) -> bool:
	var add := int((config.get("crimes", {}) as Dictionary).get(kind, 0))
	if add <= 0 or not witnessed(pos):
		return false
	_set_stars(mini(stars + add, int(config.get("max_stars", 3))))
	unseen_s = 0.0
	return true


func clear() -> void:
	unseen_s = 0.0
	_set_stars(0)


func _set_stars(n: int) -> void:
	if n == stars:
		return
	stars = n
	stars_changed.emit(stars)


func _process(delta: float) -> void:
	if stars <= 0 or get_tree().paused:
		return
	if target != null and police_sees(target.global_position):
		unseen_s = 0.0
		return
	unseen_s += delta
	var lose: Array = config.get("lose_s", [0.0, 12.0, 18.0, 25.0])
	if unseen_s >= float(lose[clampi(stars, 0, lose.size() - 1)]):
		unseen_s = 0.0
		_set_stars(stars - 1)


## "★★☆" for the HUD.
func stars_text() -> String:
	var n := int(config.get("max_stars", 3))
	return "★".repeat(stars) + "☆".repeat(maxi(n - stars, 0)) if stars > 0 else ""
