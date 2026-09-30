## Context
Godot 4 ships a high-level multiplayer API (`MultiplayerAPI`, ENet transport, `MultiplayerSpawner`, `MultiplayerSynchronizer`, RPCs). Small co-op (2–4 peers, one of them hosting) is the case it handles best. The game has no networking today; the player controller (Phase 2) and city life (Phase 3) do not exist yet either, which is exactly why the decision matters now.

## Goals / Non-Goals
- Goals: 4-player drop-in co-op with friends; works on a Deck as client and, at reduced scale, as host; no rewrite of Phase 2–4 systems when networking lands.
- Non-Goals: competitive play, anti-cheat, dedicated servers, more than 4 players, deterministic lockstep, cross-version sessions.

## How big is this, honestly
Rough addon on top of the single-player plan:

| Area | Single-player work | Co-op addon | Notes |
|---|---|---|---|
| Phase 0–1 (bootstrap, roads) | as planned | none | Pure data; unaffected. |
| Phase 2 player and vehicles | as planned | small | Peer-owned bodies plus a synchronizer each. Cheap if built with the authority rule from the start. |
| Phase 3 traffic and pedestrians | as planned | medium | Host simulates; clients receive interpolated state for nearby agents. Relevance filtering and per-player simulation bubbles are the real work. |
| Phase 4 missions and packs | as planned | medium | Missions need co-op semantics (who can trigger, shared or per-player objectives). Pack format v1 must include content hashes. |
| Phase 5 co-op itself | n/a | one dedicated change | Session, lobby, join verification, spawning, disconnect handling, tests. |

Ballpark: about a quarter more work across Phases 2–4, plus one dedicated change. A retrofit after Phase 3 without the authority rule would cost several times that.

## Decisions
- **Transport:** ENet via Godot's built-in `MultiplayerAPI`. LAN and direct IP first. No third-party networking addon.
- **Topology:** listen server. One player hosts; there is no dedicated server. The host's machine should be the strongest one; the Deck can host small sessions (target: Deck hosting 2 players within budget).
- **Authority model:**
  - A peer owns its own character and the vehicle it is driving. Other peers see interpolated state. This is the trusting model used by most indie co-op games; it avoids client prediction and feels responsive for driving, at the cost of no cheat resistance (acceptable for friends-only co-op).
  - The host owns everything else: traffic, pedestrians, mission and story state, world time, weather, tone mode, and vehicle ownership handoff when a player enters a vehicle.
  - Ownership of a vehicle transfers to the peer who enters the driver's seat; the host arbitrates conflicts.
- **Relevance:** the host replicates a world entity to a peer only if it is within that peer's interest radius (config, per entity class). Entities outside every peer's radius are simulated at low fidelity or despawned, as in single-player.
- **Streaming on the host:** chunks stay loaded around every connected player. The per-player bubble radius shrinks as player count grows, driven by a tunable so the Deck budget holds.
- **Pack verification:** on join, the client sends its pack manifest list (id, version, content hash). The host compares to its own and refuses with a message naming the mismatching pack. Pack format v1 must therefore define a content hash.
- **Drop-in and drop-out:** a joining peer spawns near the host or a chosen player. When a peer leaves, its vehicle is handed to the host and its character despawns. Mission state does not roll back.
- **Tone mode:** host-selected for the session and sent on join; clients cannot override it, because billboards, NPCs, and dialogue are shared world state.
- **Saves:** single-player saves only in this change. The host's world state is the session's truth; a persistent co-op save is a later change.

## Alternatives considered
- Host-authoritative everything with client prediction: better cheat resistance, much more work, and driving feels worse on Wi-Fi. Rejected for a friends-only game.
- Deterministic lockstep: Jolt is not deterministic across machines and the sim is large. Rejected.
- Third-party networking addons: adds a dependency and versioning risk on top of a pinned Godot. Rejected unless the built-in API proves insufficient.

## Risks / Trade-offs
- **Deck as host.** Four simulation bubbles may exceed the frame budget. Mitigation: bubble radius and agent caps scale with player count; the lobby shows a warning when a Deck hosts more than 2.
- **Internet play.** Direct IP needs port forwarding. Free options later: Steam networking sockets (if distributed on Steam), or a community relay. Both are separate decisions with the human.
- **Pack mismatch friction.** Strict hashing means everyone needs identical packs. Mitigation: the refusal message says what to install; the registry (Phase 6) can offer one-click install.
- **Testing.** Multiplayer bugs are hard to reproduce. Mitigation: gdUnit4 tests run two `MultiplayerAPI` instances in one process (Godot supports this via `SceneMultiplayer` per branch) for spawn, ownership, and disconnect cases.

## Migration Plan
- No data migration. The AGENTS.md co-op readiness rule applies to every gameplay change from Phase 2 on.
- This change is implemented after Phase 4 so missions and packs have the fields it needs.

## Open Questions
- Approve the trusting peer-owned model for player bodies? (Recommended yes for friends-only co-op.)
- Should a Deck be allowed to host 4? (Recommended: allow with a warning, verify with profiling.)
- Distribution channel: if Steam is the plan, Steam networking gives free relay and invites, which shapes the lobby design. Decide before Phase 5.
- Friendly fire and shared money: gameplay rules for co-op, to decide alongside the Phase 2 player design.
