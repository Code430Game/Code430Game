class_name WorldSync
extends Node
## Host: sends traffic and pedestrian snapshots around each client at SEND_HZ and its signal
## clock every few seconds. Client: applies them to managers running in mirror mode.

const SEND_HZ := 15.0
const REPLICATE_RADIUS_M := 350.0
const SIGNAL_SYNC_S := 5.0

var traffic: TrafficManager
var peds: PedestrianManager
var parked: ParkedCars
var player_sync: PlayerSync
var day_night: DayNight
var _accum: float = 0.0
var _signal_accum: float = 0.0


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
	_request_take.rpc_id(1, position)


@rpc("any_peer", "reliable")
func _request_take(position: Vector3) -> void:
	if not Session.is_host() or traffic == null:
		return
	var got := traffic.release_near(position)
	if got.is_empty():
		return
	_grant_take.rpc_id(multiplayer.get_remote_sender_id(), got["transform"], got["color"], got["vehicle"], got["station"])


@rpc("authority", "reliable")
func _grant_take(transform: Transform3D, color: Color, vehicle_id: String, station: String = "") -> void:
	take_granted.emit(transform, color, vehicle_id, station)


## Guest: asks the host for the parked car in stall `key` (parked cars are the same on every
## peer, so the stall key names it); the answer arrives like a traffic car's, via take_granted.
func request_take_parked(key: String) -> void:
	_request_take_parked.rpc_id(1, key)


@rpc("any_peer", "reliable")
func _request_take_parked(key: String) -> void:
	if not Session.is_host() or parked == null:
		return
	var got := parked.release_key(key)  # also tells every peer the stall is empty (stall_taken)
	if got.is_empty():
		return
	_grant_take.rpc_id(multiplayer.get_remote_sender_id(), got["transform"], got["color"], got["vehicle"], got["station"])


## Host: tells the guests that a stall was emptied (by anyone), so their copies match.
func announce_stall_taken(key: String) -> void:
	if Session.is_host() and Session.connected:
		_stall_taken.rpc(key)


@rpc("authority", "call_remote", "reliable")
func _stall_taken(key: String) -> void:
	if parked != null:
		parked.mark_taken(key)


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
