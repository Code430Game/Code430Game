## 0. Preconditions
- [ ] 0.1 Human approves the authority model and this change
- [ ] 0.2 Phase 2 player and vehicle controllers exist and follow the AGENTS.md co-op readiness rule
- [ ] 0.3 Pack format v1 defines a content hash per pack

## 1. Session core
- [ ] 1.1 `game/core/net/session.gd`: host, join, leave, peer list, max 4 players (tunable)
- [ ] 1.2 Pack manifest exchange and verification on join with readable refusal messages
- [ ] 1.3 Tone mode sent on join; clients locked to the host's mode
- [ ] 1.4 gdUnit4 tests with two in-process `MultiplayerAPI` instances: join, refuse when full, refuse on pack mismatch

## 2. Players and vehicles
- [ ] 2.1 Peer-owned character spawning via `MultiplayerSpawner`, interpolation for remote peers
- [ ] 2.2 Vehicle ownership transfer on enter/exit, host arbitration on conflict
- [ ] 2.3 Disconnect handling: vehicle to host, character despawn
- [ ] 2.4 Tests: ownership transfer, disconnect while driving

## 3. World replication
- [ ] 3.1 Interest radius per entity class in config; host-side relevance filter
- [ ] 3.2 Traffic and pedestrian state replication with interpolation
- [ ] 3.3 Host streaming keeps chunks loaded around every player; bubble radius scales with player count
- [ ] 3.4 Mission and story state replication (shared objectives by default)
- [ ] 3.5 Tests: distant entities not replicated, bubble scaling

## 4. Lobby UI
- [ ] 4.1 Host/join screen usable with a controller in Deck Game Mode (direct IP entry via on-screen keyboard)
- [ ] 4.2 Player list, tone mode display, "Deck host" warning above two players
- [ ] 4.3 Join failure messages shown in full

## 5. Verification
- [ ] 5.1 Profile: Deck hosting two clients, record frame time in the PR
- [ ] 5.2 **Stop: human plays a four-player session (three Deck or PC clients) and reports**
