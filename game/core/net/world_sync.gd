class_name WorldSync
extends Node
## Host: sends traffic and pedestrian snapshots around each client at SEND_HZ and its signal
## clock every few seconds. Client: applies them to managers running in mirror mode.
##
## Taking cars: a guest asks, the host checks the asker is in the session and within
## `take_reach_m` of the car or stall, and grants it. The guest only acts on a grant it is
## waiting for, so a late or repeated grant never makes a second car. A guest who joins later
## is sent the stalls already emptied.

const SEND_HZ := 15.0
const REPLICATE_RADIUS_M := 350.0
const SIGNAL_SYNC_S := 5.0
const CONFIG_PATH := "res://core/net/net_config.json"

var traffic: TrafficManager
var peds: PedestrianManager
var parked: ParkedCars
var player_sync: PlayerSync
var day_night: DayNight
var config: Dictionary = {}
var _accum: float = 0.0
var _signal_accum: float = 0.0
var _take_pending: bool = false  # guest: a take was asked for and not yet granted


func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	config = data if data is Dictionary else {}
	Session.peer_joined.connect(_on_peer_joined)


func _process(delta: float) -> void:
	if not Session.is_host() or not Session.connected or traffic == null:
		return
	_accum += delta
	_signal_accum += delta
	if _accum >= 1.0 / SEND_HZ:
		_accum = 0.0
		for id in Session.peers:
			if int(id) == 1:
				continue
			var r: RemotePlayer = player_sync.remotes.get(int(id)) if player_sync != null else null
			var around := r.controlled_position() if r != null else Vector3.ZERO
			_traffic_snapshot.rpc_id(int(id), traffic.snapshot(around, REPLICATE_RADIUS_M))
			if peds != null:
				_peds_snapshot.rpc_id(int(id), peds.snapshot(around, REPLICATE_RADIUS_M))
	if _signal_accum >= SIGNAL_SYNC_S:
		_signal_accum = 0.0
		_signal_time.rpc(traffic.signals.time, day_night.hour if day_night != null else -1.0)


## Guest: asks the host for the traffic car at `position`; the answer spawns a car via `take_granted`.
signal take_granted(transform: Transform3D, color: Color, vehicle_id: String, station: String)


func request_take(position: Vector3) -> void:
	_take_pending = true
	_request_take.rpc_id(1, position)


## Guest: whether a take is waiting for the host's answer.
func take_pending() -> bool:
	return _take_pending


@rpc("any_peer", "reliable")
func _request_take(position: Vector3) -> void:
	if not Session.is_host() or traffic == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not may_take(sender, position):
		return
	var got := traffic.release_near(position)
	if got.is_empty():
		return
	_grant_take.rpc_id(sender, got["transform"], got["color"], got["vehicle"], got["station"])


## Host: whether peer `sender` may take the car at `at`: a player in this session whose body
## (or car) is within `take_reach_m` of it.
func may_take(sender: int, at: Vector3) -> bool:
	var r: RemotePlayer = player_sync.remotes.get(sender) if player_sync != null else null
	var from := r.controlled_position() if r != null else Vector3.INF
	return within_reach(Session.peers, sender, from, at, float(config.get("take_reach_m", 8.0)))


## Whether `sender` is one of `peers` (not the host) and `from` is within `reach` of `at`.
static func within_reach(peers: Dictionary, sender: int, from: Vector3, at: Vector3, reach: float) -> bool:
	if sender == 1 or not peers.has(sender) or from == Vector3.INF:
		return false
	return from.distance_to(at) <= reach


@rpc("authority", "reliable")
func _grant_take(transform: Transform3D, color: Color, vehicle_id: String, station: String = "") -> void:
	if not _take_pending:
		return  # nothing asked for (a late or repeated answer): no second car
	_take_pending = false
	take_granted.emit(transform, color, vehicle_id, station)


## Guest: asks the host for the parked car in stall `key` (parked cars are the same on every
## peer, so the stall key names it); the answer arrives like a traffic car's, via take_granted.
func request_take_parked(key: String) -> void:
	_take_pending = true
	_request_take_parked.rpc_id(1, key)


@rpc("any_peer", "reliable")
func _request_take_parked(key: String) -> void:
	if not Session.is_host() or parked == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	var at := parked.position_of(key)
	if at == Vector3.INF or not may_take(sender, at):
		return
	var got := parked.release_key(key)  # also tells every peer the stall is empty (stall_taken)
	if got.is_empty():
		return
	_grant_take.rpc_id(sender, got["transform"], got["color"], got["vehicle"], got["station"])


## Host: tells the guests that a stall was emptied (by anyone), so their copies match.
func announce_stall_taken(key: String) -> void:
	if Session.is_host() and Session.connected:
		_stall_taken.rpc(key)


@rpc("authority", "call_remote", "reliable")
func _stall_taken(key: String) -> void:
	if parked != null:
		parked.mark_taken(key)


## Host: a guest joined; send it the stalls already emptied this session (after its welcome,
## on the same reliable channel).
func _on_peer_joined(id: int, _info: Dictionary) -> void:
	if not Session.is_host() or id == 1 or parked == null:
		return
	var keys := taken_stalls()
	if not keys.is_empty():
		_stalls_taken.rpc_id(id, keys)


## Host: the keys of every stall emptied this session, sorted.
func taken_stalls() -> PackedStringArray:
	var keys := PackedStringArray()
	for k in parked.taken:
		keys.append(str(k))
	keys.sort()
	return keys


@rpc("authority", "call_remote", "reliable")
func _stalls_taken(keys: PackedStringArray) -> void:
	if parked != null:
		for k in keys:
			parked.mark_taken(k)


## Guest: tells the host one of its cars was hit here.
func report_hit(position: Vector3, velocity: Vector3) -> void:
	_report_hit.rpc_id(1, position, velocity)


@rpc("any_peer", "unreliable")
func _report_hit(position: Vector3, velocity: Vector3) -> void:
	if Session.is_host() and traffic != null:
		traffic.hit_near(position, velocity)


@rpc("authority", "unreliable")
func _traffic_snapshot(data: PackedFloat32Array) -> void:
	if traffic != null:
		traffic.apply_snapshot(data)


@rpc("authority", "unreliable")
func _peds_snapshot(data: PackedFloat32Array) -> void:
	if peds != null:
		peds.apply_snapshot(data)


@rpc("authority", "reliable")
func _signal_time(t: float, hour: float) -> void:
	if traffic != null:
		traffic.signals.time = t
	if day_night != null and hour >= 0.0:
		day_night.hour = hour
