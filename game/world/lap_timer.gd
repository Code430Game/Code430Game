class_name LapTimer
extends RefCounted
## Times laps across a map pack's start lines (`lap.v0.json`, add-proving-ground).
##
## Approach: each lap has a start point, a direction of travel and a half width. Every update
## takes the player's signed distance along the direction from the start point; a crossing is
## that distance going from behind the line to past it while the player is within the half
## width sideways, with a re-arm delay so a reverse over the line does not count twice. The
## first crossing starts a lap, each later one ends it and starts the next, and the best of
## the session is kept. Off the loop (no road with one of the lap's names nearby) the timer
## resets and the readout hides. Local to each player; nothing is replicated.

const LOOP_NEAR_M := 20.0
## A road more than this far above or below the player is another level (the street under
## the viaduct), not the one they are on.
const LOOP_LEVEL_M := 4.0
const FILE_NAME := "lap.v0.json"

var laps: Array[Dictionary] = []
## Seconds into the current lap, or -1.0 when no lap is running.
var current_s: float = -1.0
## Best completed lap this session, or INF when none has been completed.
var best_s: float = INF
## Seconds of the lap that just finished, or -1.0.
var last_s: float = -1.0
## True while the player is on a loop road: the HUD shows the readout only then.
var visible: bool = false
var _prev_along: Dictionary = {}  # lap id -> last signed distance along the direction
var _rearm: Dictionary = {}  # lap id -> seconds left before the line counts again


## Reads the pack's laps. Returns false (and keeps no laps) when the pack has none.
func load(pack_dir: String) -> bool:
	laps = []
	var path := pack_dir.path_join(FILE_NAME)
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not (parsed.get("laps") is Array):
		push_warning("LapTimer: %s is not a lap file" % path)
		return false
	for lap in parsed["laps"]:
		if lap is Dictionary and lap.has("start") and lap.has("direction"):
			laps.append(lap)
	return not laps.is_empty()


## Uses laps built in code (tests).
func set_laps(entries: Array[Dictionary]) -> void:
	laps = entries
	_prev_along.clear()
	_rearm.clear()


## Steps the timer with the player's position. `graph` tells whether the player is on the loop.
func update(position: Vector3, graph: RoadGraph, delta: float) -> void:
	if laps.is_empty():
		visible = false
		return
	visible = _on_loop(position, graph)
	if not visible:
		current_s = -1.0
		for lap in laps:
			_prev_along[str(lap["id"])] = _along(lap, position)
		return
	if current_s >= 0.0:
		current_s += delta
	for lap in laps:
		var id := str(lap["id"])
		var along := _along(lap, position)
		var prev: float = _prev_along.get(id, along)
		_prev_along[id] = along
		_rearm[id] = maxf(float(_rearm.get(id, 0.0)) - delta, 0.0)
		var half := float(lap.get("half_width_m", 16.0))
		if prev < 0.0 and along >= 0.0 and absf(_across(lap, position)) <= half and float(_rearm[id]) <= 0.0:
			_cross(lap)


func _cross(lap: Dictionary) -> void:
	_rearm[str(lap["id"])] = float(lap.get("rearm_s", 10.0))
	if current_s >= 0.0:
		last_s = current_s
		best_s = minf(best_s, current_s)
	current_s = 0.0


## Signed distance along the lap's direction from its start point.
func _along(lap: Dictionary, position: Vector3) -> float:
	var d := _direction(lap)
	var s: Dictionary = lap["start"]
	return (position.x - float(s["x"])) * d.x + (position.z - float(s["z"])) * d.y


## Signed distance across the line (positive to the right of the direction).
func _across(lap: Dictionary, position: Vector3) -> float:
	var d := _direction(lap)
	var s: Dictionary = lap["start"]
	return -(position.x - float(s["x"])) * d.y + (position.z - float(s["z"])) * d.x


func _direction(lap: Dictionary) -> Vector2:
	var dir: Dictionary = lap["direction"]
	var d := Vector2(float(dir["x"]), float(dir["z"]))
	return d.normalized() if d.length_squared() > 0.0 else Vector2(0.0, 1.0)


func _on_loop(position: Vector3, graph: RoadGraph) -> bool:
	if graph == null:
		return false
	var hit := graph.nearest_edge(position, LOOP_NEAR_M, LOOP_LEVEL_M)
	if hit.is_empty():
		return false
	var name: String = hit["edge"].name
	for lap in laps:
		for n in lap.get("loop_names", []):
			if str(n) == name:
				return true
	return false


## "LAP 0:42.3   BEST 1:31.0", or the current lap alone before any lap is complete.
func readout() -> String:
	if current_s < 0.0:
		return "LAP  --:--.-" if best_s == INF else "LAP  --:--.-   BEST %s" % format_time(best_s)
	var text := "LAP  %s" % format_time(current_s)
	if best_s != INF:
		text += "   BEST %s" % format_time(best_s)
	return text


## m:ss.t
static func format_time(seconds: float) -> String:
	var whole := int(floor(seconds))
	var tenths := int(floor((seconds - whole) * 10.0))
	return "%d:%02d.%d" % [whole / 60, whole % 60, tenths]
