# Design: drop-in co-op

## Transport and roles
- Godot high-level multiplayer over ENet. The host is peer 1 and runs the world; clients own
  only their character and the car they drive. Default port 43010. LAN and direct IP; an
  internet relay is a later decision.
- `Session` autoload (`core/net/session.gd`): `host(port)`, `join(address, port)`, `leave()`.
  On connect the client sends `hello(manifest)` with its pack id, version and content hash; the
  host answers `welcome(peers, pack, signal_time)` or `refuse(reason)` and drops the peer.
  Capacity is `max_players` (4). Signals: `peer_joined`, `peer_left`, `joined`, `refused`.
- The pack content hash is SHA-256 over `pack.json` plus the names and sizes of every file in
  the pack, computed by `MapPack.content_hash()` on both sides. Mismatch refuses the join with
  the differing field named.

## Players and vehicles
- Each peer simulates its own character and car locally and broadcasts state at 20 Hz with an
  unreliable RPC: on foot or driving, character position and yaw, car transform and velocity.
- Every other peer shows a `RemotePlayer`: a capsule and a car replica built from `CarMesh`
  in that peer's colour, interpolated 100 ms behind the newest state. The car replica is an
  `AnimatableBody3D` so local physics bumps against it. The owner does not feel the bump; good
  enough for a first pass.
- Vehicle ownership is implicit: whoever drives a car simulates it. Taking a traffic car is
  host-only in this pass (a client asks the host, which is deferred).

## World replication
- Host simulates traffic, pedestrians and signals with anchors at every player. Clients run
  their managers in mirror mode: no spawning or stepping; `apply_snapshot` fills the agents
  from the host's packet and renders them. Clients still assign pooled bodies to nearby
  mirrored agents so cars feel solid; a client-side hit does not retire the host's agent.
- Snapshots: 15 Hz unreliable, `PackedFloat32Array` of x, y, z, yaw and colour index per agent,
  only agents within `replicate_radius_m` (350) of that client. Pedestrians the same.
- Signals are deterministic from a clock; the host sends its clock in `welcome` and every 5 s.
- Streaming: the host's streamer anchors at every player; clients anchor on themselves.

## Lobby
- Pause menu gains Host, Join (address field; the Deck's on-screen keyboard fills it) and a
  player list. Testbed flags `--host[=port]` and `--join=address[:port]` for automation.
- Joining players spawn at the host's spawn point, staggered 8 m apart along the road.

## Budget
- Host: one bubble of traffic per player. The Deck host target is two players; the lobby
  shows a warning above that.
