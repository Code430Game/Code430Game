class_name PlayerSync
extends Node
## Broadcasts the local player's state at SEND_HZ and feeds remote peers' RemotePlayer nodes.
## Lives in the scene; the scene gives it the local Player and a parent for remote replicas.

const SEND_HZ := 20.0

## A remote peer started sounding their horn at `position` (the host startles its pedestrians).
signal remote_horn(position: Vector3)

var player: Player
var remote_parent: Node3D
var remotes: Dictionary = {}  # peer id -> RemotePlayer
var _accum: float = 0.0


func _ready() -> void:
	Session.peer_joined.connect(_on_peer_joined)
	Session.peer_left.connect(_on_peer_left)
	Session.peer_profile_changed.connect(_on_peer_profile_changed)
	Session.session_ended.connect(_clear)


func _on_peer_joined(id: int, info: Dictionary) -> void:
	if id == multiplayer.get_unique_id() or remotes.has(id) or remote_parent == null:
		return
	var r := RemotePlayer.new()
	r.name = "peer_%d" % id
	remote_parent.add_child(r)
	r.setup(id, info.get("color", Color.WHITE), info.get("profile", {}))
	remotes[id] = r


func _on_peer_profile_changed(id: int, profile: Dictionary) -> void:
	var r: RemotePlayer = remotes.get(id)
	if r != null:
		r.apply_profile(profile)


func _on_peer_left(id: int) -> void:
	var r: RemotePlayer = remotes.get(id)
	if r != null:
		r.queue_free()
		remotes.erase(id)


func _clear() -> void:
	for id in remotes.keys():
		_on_peer_left(id)


## Positions of every remote peer's controlled body, for the host's traffic and streaming anchors.
func remote_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for id in remotes:
		out.append((remotes[id] as RemotePlayer).controlled_position())
	return out


func _process(delta: float) -> void:
	if not Session.connected or player == null or (Session.is_client() and Session.peers.is_empty()):
		return  # not up yet, or still waiting for the welcome
	_accum += delta
	if _accum < 1.0 / SEND_HZ:
		return
	_accum = 0.0
	var car_t := Transform3D.IDENTITY
	var vehicle := -1
	var car_color := Color.WHITE
	if player.is_driving():
		car_t = player.vehicle.global_transform
		vehicle = RemotePlayer.HELICOPTER_INDEX if player.vehicle is FlyableHelicopter else VehicleCatalogue.index_of(str(player.vehicle.get("vehicle_id")))
		car_color = player.vehicle.get("body_color")
	var horn := player.is_driving() and Input.is_action_pressed("horn") and not get_tree().paused
	_state.rpc(player.is_driving(), player.global_transform, car_t, vehicle, car_color, horn)


@rpc("any_peer", "unreliable")
func _state(is_driving: bool, body_t: Transform3D, car_t: Transform3D, vehicle: int = -1, car_color: Color = Color.WHITE, horn: bool = false) -> void:
	var id := multiplayer.get_remote_sender_id()
	var r: RemotePlayer = remotes.get(id)
	if r == null:
		return
	r.push_state(is_driving, body_t, car_t)
	if is_driving:
		r.set_vehicle(RemotePlayer.HELICOPTER_ID if vehicle == RemotePlayer.HELICOPTER_INDEX else VehicleCatalogue.id_at(vehicle), car_color)
	var sounding := horn and is_driving
	if sounding and not r.horn.sounding:
		remote_horn.emit(car_t.origin)
	r.horn.sounding = sounding
