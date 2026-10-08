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
## This peer's map pack summary: {"id", "version", "hash"}; set by the scene before hosting or joining.
var local_manifest: Dictionary = {}
## This peer's whole enabled pack set, `[{"id", "version", "hash"}]` sorted by id
## (PackLoader.manifest_summary); the host's set is the session's (add-pack-loader).
var local_packs: Array = []
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
	ContentMode.mode_changed.connect(_on_mode_changed)
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
	if ContentMode.locked:
		ContentMode.locked = false
		ContentMode.load_saved()
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
	_hello.rpc_id(1, local_manifest, _pending_name, local_profile, ContentMode.current, local_packs)


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


## Pure check over whole pack sets (both sorted by id): "" when they match, else the first
## difference: a pack missing on either side, or a version or hash that differs.
static func pack_set_mismatch(host_packs: Array, guest_packs: Array) -> String:
	var guest_by_id := {}
	for row: Dictionary in guest_packs:
		guest_by_id[str(row.get("id", ""))] = row
	var host_by_id := {}
	for row: Dictionary in host_packs:
		host_by_id[str(row.get("id", ""))] = row
	for row: Dictionary in host_packs:
		var id := str(row.get("id", ""))
		if not guest_by_id.has(id):
			return "pack %s missing on your side (host has %s)" % [id, row.get("version", "?")]
		var theirs: Dictionary = guest_by_id[id]
		if str(row.get("version", "")) != str(theirs.get("version", "")):
			return "pack %s: host has %s, you have %s" % [id, row.get("version", "?"), theirs.get("version", "?")]
		if str(row.get("hash", "")) != str(theirs.get("hash", "")):
			return "pack %s differs from the host's copy (same version %s, different contents)" % [id, row.get("version", "?")]
	for row: Dictionary in guest_packs:
		var id := str(row.get("id", ""))
		if not host_by_id.has(id):
			return "pack %s is not enabled on the host" % id
	return ""


@rpc("any_peer", "reliable")
func _hello(manifest: Dictionary, name: String, profile: Dictionary = {}, _mode: String = "", packs: Array = []) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if peers.size() >= max_players:
		reason = "the game is full (%d players)" % max_players
	elif not local_packs.is_empty() or not packs.is_empty():
		reason = pack_set_mismatch(local_packs, packs)
	else:
		reason = mismatch_reason(local_manifest, manifest)
	if reason != "":
		print("net: refusing peer %d: %s" % [id, reason])
		_refuse.rpc_id(id, reason)
		_kick_later(id)
		return
	print("net: peer %d joined as %s (%d players)" % [id, name, peers.size() + 1])
	peers[id] = {"name": name, "color": _color_for(id), "profile": profile}
	_welcome.rpc_id(id, peers, local_manifest, signal_time, ContentMode.current, local_packs)
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
func _welcome(all_peers: Dictionary, host_manifest: Dictionary, host_signal_time: float, mode: String = "", host_packs: Array = []) -> void:
	peers = all_peers
	signal_time = host_signal_time
	if mode != "":
		ContentMode.set_mode(mode, false)  # the host's tone is the session's
		ContentMode.locked = true
	print("net: welcomed as peer %d with %d players" % [multiplayer.get_unique_id(), peers.size()])
	joined.emit({"peers": peers, "pack": host_manifest, "packs": host_packs})
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


## Host: a tone change mid-session reaches every client.
func _on_mode_changed(id: String) -> void:
	if is_host():
		_mode_changed.rpc(id)


@rpc("authority", "reliable")
func _mode_changed(id: String) -> void:
	ContentMode.set_mode(id, false)
	ContentMode.locked = true


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
