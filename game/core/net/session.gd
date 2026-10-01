extends Node
## Session autoload: host or join a co-op game over ENet. The host is peer 1 and owns the
## world. A joining peer sends its pack manifest; the host verifies it against its own and
## either welcomes the peer or refuses with a readable reason. See add-coop-multiplayer.

signal peer_joined(peer_id: int, info: Dictionary)
signal peer_left(peer_id: int)
signal joined(info: Dictionary)
signal refused(reason: String)
signal session_ended
signal peer_profile_changed(peer_id: int, profile: Dictionary)

const DEFAULT_PORT := 43010
const MAX_PLAYERS := 4

var max_players: int = MAX_PLAYERS
## This peer's pack summary: {"id", "version", "hash"}; set by the scene before hosting or joining.
var local_manifest: Dictionary = {}
## Peer id -> {"name", "color", "profile"} for every player in the session, including this one.
var peers: Dictionary = {}
## This player's CharacterProfile, sent with hello and welcome; set by the scene.
var local_profile: Dictionary = {}
var role: String = "offline"  # offline | host | client
## True once the transport is up: hosting, or connected to the host (before the welcome).
var connected: bool = false
var signal_time: float = 0.0
var _peer: ENetMultiplayerPeer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func() -> void: refused.emit("could not reach the host"); _reset())
	multiplayer.server_disconnected.connect(func() -> void: _reset(); session_ended.emit())


func is_host() -> bool:
	return role == "host"


func is_client() -> bool:
	return role == "client"


func is_online() -> bool:
	return role != "offline"


func player_count() -> int:
	return peers.size()


## Starts hosting on `port`. Returns an Error.
func host(port: int = DEFAULT_PORT, name: String = "host") -> Error:
	_peer = ENetMultiplayerPeer.new()
	# Bind IPv4 explicitly: the default wildcard is an IPv6 socket, and on hosts where
	# IPv6 sockets do not accept IPv4 (SteamOS as shipped) nobody could ever connect.
	_peer.set_bind_ip("0.0.0.0")
	var err := _peer.create_server(port, max_players - 1)
	if err != OK:
		push_error("Session: cannot host on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = _peer
	role = "host"
	connected = true
	peers = {1: {"name": name, "color": _color_for(1), "profile": local_profile}}
	print("net: hosting on port %d" % port)
	peer_joined.emit(1, peers[1])
	return OK


## Connects to a host. The outcome arrives as `joined` or `refused`.
func join(address: String, port: int = DEFAULT_PORT, name: String = "guest") -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		push_error("Session: cannot connect to %s:%d: %s" % [address, port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = _peer
	role = "client"
	peers = {}
	_pending_name = name
	return OK


var _pending_name: String = "guest"


func leave() -> void:
	if role == "offline":
		return
	_reset()
	session_ended.emit()


func _reset() -> void:
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	role = "offline"
	connected = false
	peers = {}


func _on_connected_to_server() -> void:
	connected = true
	print("net: connected to host, sending hello")
	_hello.rpc_id(1, local_manifest, _pending_name, local_profile)


func _on_peer_connected(id: int) -> void:
	pass  # the host waits for hello; clients learn about peers from welcome and peer_joined


func _on_peer_disconnected(id: int) -> void:
	if peers.erase(id):
		peer_left.emit(id)
	if is_host():
		_peer_gone.rpc(id)


## Pure check used by the host: "" when the manifests match, else the reason.
static func mismatch_reason(host_manifest: Dictionary, guest_manifest: Dictionary) -> String:
	for key in ["id", "version", "hash"]:
		if str(host_manifest.get(key, "")) != str(guest_manifest.get(key, "")):
			return "pack %s differs: host has %s, you have %s" % [key, host_manifest.get(key, "?"), guest_manifest.get(key, "?")]
	return ""


@rpc("any_peer", "reliable")
func _hello(manifest: Dictionary, name: String, profile: Dictionary = {}) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if peers.size() >= max_players:
		reason = "the game is full (%d players)" % max_players
	else:
		reason = mismatch_reason(local_manifest, manifest)
	if reason != "":
		print("net: refusing peer %d: %s" % [id, reason])
		_refuse.rpc_id(id, reason)
		_kick_later(id)
		return
	print("net: peer %d joined as %s (%d players)" % [id, name, peers.size() + 1])
	peers[id] = {"name": name, "color": _color_for(id), "profile": profile}
	_welcome.rpc_id(id, peers, local_manifest, signal_time)
	_peer_came.rpc(id, peers[id])
	peer_joined.emit(id, peers[id])


func _kick_later(id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_peer.disconnect_peer(id)


@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	print("net: refused: %s" % reason)
	refused.emit(reason)
	_reset()


@rpc("authority", "reliable")
func _welcome(all_peers: Dictionary, host_manifest: Dictionary, host_signal_time: float) -> void:
	peers = all_peers
	signal_time = host_signal_time
	print("net: welcomed as peer %d with %d players" % [multiplayer.get_unique_id(), peers.size()])
	joined.emit({"peers": peers, "pack": host_manifest})
	for id in peers:
		peer_joined.emit(int(id), peers[id])


@rpc("authority", "reliable")
func _peer_came(id: int, info: Dictionary) -> void:
	if id == multiplayer.get_unique_id() or peers.has(id):
		return
	peers[id] = info
	peer_joined.emit(id, info)


@rpc("authority", "reliable")
func _peer_gone(id: int) -> void:
	if peers.erase(id):
		peer_left.emit(id)


## Changes this player's look; everyone in the session hears about it.
func set_profile(profile: Dictionary) -> void:
	local_profile = profile
	if not is_online():
		return
	var me := multiplayer.get_unique_id()
	if peers.has(me):
		peers[me]["profile"] = profile
	_profile_changed.rpc(profile)


@rpc("any_peer", "reliable")
func _profile_changed(profile: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	peers[id]["profile"] = profile
	peer_profile_changed.emit(id, profile)


## Host: pushes its signal clock so clients run the same light phases.
@rpc("authority", "unreliable")
func sync_signal_time(t: float) -> void:
	signal_time = t


## This machine's LAN addresses (IPv4, not loopback), for the host to read out to friends.
static func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


static func _color_for(peer_id: int) -> Color:
	var palette := [Color(0.85, 0.25, 0.2), Color(0.2, 0.5, 0.9), Color(0.25, 0.7, 0.35), Color(0.9, 0.75, 0.2), Color(0.7, 0.35, 0.8)]
	return palette[(peer_id - 1) % palette.size()]
