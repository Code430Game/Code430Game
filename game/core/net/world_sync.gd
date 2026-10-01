class_name WorldSync
extends Node
## Host: sends traffic and pedestrian snapshots around each client at SEND_HZ and its signal
## clock every few seconds. Client: applies them to managers running in mirror mode.

const SEND_HZ := 15.0
const REPLICATE_RADIUS_M := 350.0
const SIGNAL_SYNC_S := 5.0

var traffic: TrafficManager
var peds: PedestrianManager
var player_sync: PlayerSync
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
		_signal_time.rpc(traffic.signals.time)


@rpc("authority", "unreliable")
func _traffic_snapshot(data: PackedFloat32Array) -> void:
	if traffic != null:
		traffic.apply_snapshot(data)


@rpc("authority", "unreliable")
func _peds_snapshot(data: PackedFloat32Array) -> void:
	if peds != null:
		peds.apply_snapshot(data)


@rpc("authority", "reliable")
func _signal_time(t: float) -> void:
	if traffic != null:
		traffic.signals.time = t
