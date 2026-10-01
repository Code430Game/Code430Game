## 0. Preconditions
- [x] 0.1 Human approves the authority model and this change (2026-09-30; co-op started 2026-10-01 on request)
- [x] 0.2 Phase 2 player and vehicle controllers exist and follow the AGENTS.md co-op readiness rule
- [x] 0.3 Pack content hash computed at runtime by MapPack.content_hash (design.md); manifest field deferred

## 1. Session core
- [x] 1.1 `game/core/net/session.gd`: host, join, leave, peer list, max 4 players (tunable)
- [x] 1.2 Pack manifest exchange and verification on join with readable refusal messages
- [ ] 1.3 Tone mode sent on join; clients locked to the host's mode (waits for add-content-modes)
- [x] 1.4 Tests: manifest mismatch reasons (unit); join verified with two local instances on the Mac (host + client over loopback, 2026-10-01); in-process two-API test deferred

## 2. Players and vehicles
- [x] 2.1 Peer-owned character and car, broadcast at 20 Hz, RemotePlayer replicas interpolated 100 ms behind (no MultiplayerSpawner: manual RPC state)
- [x] 2.2 Each peer drives its own car; a guest takes a traffic car by asking the host, which removes the agent and grants the car's transform and colour; guest hits on the host's cars are reported and retire them on the host; guests spawn in the first clear slot (2026-10-01)
- [x] 2.3 Disconnect handling: replica despawn on peer_left; session_ended returns a client to single-player simulation
- [x] 2.4 Tests: remote interpolation, snapshot round trip (ownership transfer deferred with 2.2)

## 3. World replication
- [x] 3.1 Replicate radius 350 m per client (WorldSync.REPLICATE_RADIUS_M); host filters per client
- [x] 3.2 Traffic and pedestrian snapshots at 15 Hz into mirror-mode managers (no interpolation yet; 15 Hz reads fine at traffic speeds)
- [x] 3.3 Host streaming, traffic and pedestrian anchors include every remote player
- [ ] 3.4 Mission and story state replication (no missions exist yet)
- [x] 3.5 Test: agents beyond the radius are left out of the snapshot

## 4. Lobby UI
- [x] 4.1 Pause menu: Host, Join with an address field (right on Join focuses it for the on-screen keyboard); flags --host and --join
- [x] 4.2 Player list and Deck host warning above two players in the pause menu status line (tone mode later)
- [x] 4.3 Join failure messages shown in full in the status line

## 5. Verification
- [ ] 5.1 Profile: Deck hosting two clients, record frame time in the PR
- [ ] 5.2 **Stop: human plays a four-player session (three Deck or PC clients) and reports**
