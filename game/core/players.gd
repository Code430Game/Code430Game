extends Node
## Players autoload: every player by peer id. No gameplay code holds "the player";
## it asks here. Single-player registers the local player under LOCAL_PEER_ID.
## Co-op later registers remote peers with their own ids (see add-coop-multiplayer).

signal player_registered(peer_id: int, player: Node)
signal player_unregistered(peer_id: int)

const LOCAL_PEER_ID := 1

var _players: Dictionary = {}  # peer id -> Node (the character)


## Registers a player's character for a peer id, replacing any previous entry.
func register(peer_id: int, player: Node) -> void:
	_players[peer_id] = player
	player_registered.emit(peer_id, player)


## Removes a peer's player.
func unregister(peer_id: int) -> void:
	if _players.erase(peer_id):
		player_unregistered.emit(peer_id)


## The local player's character, or null before spawn.
func local() -> Node:
	return _players.get(LOCAL_PEER_ID)


## All registered characters keyed by peer id.
func all() -> Dictionary:
	return _players.duplicate()


## The node the local player currently controls: their car when driving, else their character.
func local_controlled_body() -> Node3D:
	var p := local()
	if p == null:
		return null
	if p.has_method("controlled_body"):
		return p.controlled_body()
	return p


## Removes every player (scene changes, tests).
func clear() -> void:
	for peer_id in _players.keys():
		unregister(peer_id)
