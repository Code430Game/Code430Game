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
## True while the police helicopter can see the target (set each frame by the PoliceManager).
var helicopter_sees: bool = false
## True while a police car or officer has the target in sight (updated each frame while wanted).
var ground_sees: bool = false


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


## True when a police car or officer is within sight of `pos` (`sight` metres; -1: the usual
## `police_sight_m`).
func police_sees(pos: Vector3, sight: float = -1.0) -> bool:
	var r := sight if sight > 0.0 else float(config.get("police_sight_m", 55.0))
	for p in police_positions:
		if p.distance_to(pos) <= r:
			return true
	return false


## A crime of `kind` (see `crimes` in the config) at `pos`. `seen`: the police saw it
## themselves (an officer was hit), so it counts without a witness check. Returns true when it
## counted.
func report(kind: String, pos: Vector3, seen: bool = false) -> bool:
	var add := int((config.get("crimes", {}) as Dictionary).get(kind, 0))
	if add <= 0 or not (seen or witnessed(pos)):
		return false
	_set_stars(mini(stars + add, int(config.get("max_stars", 3))))
	unseen_s = 0.0
	return true


## Sets the level directly (screenshots, tests, debug).
func set_stars(n: int) -> void:
	unseen_s = 0.0
	_set_stars(clampi(n, 0, int(config.get("max_stars", 3))))


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
		ground_sees = false
		return
	ground_sees = target != null and police_sees(target.global_position, sight_m())
	if target != null and seen():
		unseen_s = 0.0
		return
	unseen_s += delta
	if unseen_s >= lose_s():
		unseen_s = 0.0
		_set_stars(stars - 1)


## True while wanted and somebody in the police (a car, an officer, the helicopter) sees the
## target (update-police-pursuit 1.1).
func seen() -> bool:
	return stars > 0 and (helicopter_sees or ground_sees)


## How far ground units see the target: `aircraft_sight_m` while it flies an aircraft off the
## ground (add-flyable-helicopter), else `police_sight_m`.
func sight_m() -> float:
	if target is FlyableHelicopter and (target as FlyableHelicopter).airborne():
		return float(config.get("aircraft_sight_m", 150.0))
	return float(config.get("police_sight_m", 55.0))


## Seconds out of sight the current level needs to drop a star.
func lose_s() -> float:
	var lose: Array = config.get("lose_s", [0.0, 12.0, 18.0, 25.0])
	return float(lose[clampi(stars, 0, lose.size() - 1)])


## How far the hidden player is toward losing the current star: 0 when seen or not wanted,
## up to 1 as the time unseen reaches `lose_s()`.
func hidden_progress() -> float:
	if stars <= 0 or seen():
		return 0.0
	return clampf(unseen_s / maxf(lose_s(), 0.001), 0.0, 1.0)


## "★★☆" for the HUD.
func stars_text() -> String:
	var n := int(config.get("max_stars", 3))
	return "★".repeat(stars) + "☆".repeat(maxi(n - stars, 0)) if stars > 0 else ""
