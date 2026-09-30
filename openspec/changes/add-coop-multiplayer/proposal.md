# Change: Add drop-in co-op for up to 4 players

**Status: PROPOSED, not approved.** Written at the human's request to explore the cost of small-group multiplayer. Not scheduled before Phases 0–1. Depends on the Phase 2 player controller existing.

## Why
The human wants to play the city with a few friends. VISION.md originally said "not multiplayer"; the revised vision (pillar 8) makes small-group co-op a goal. Deciding this now is cheap and deciding it after Phase 3 is expensive, because traffic, pedestrians, and missions are much harder to make replicable after the fact than to build replicable from the start.

## What Changes
- New capability `coop-session`: host/join a session for up to 4 players over Godot's built-in ENet high-level multiplayer, LAN and direct IP first.
- Lobby and join flow that works from the Steam Deck UI with a controller, with drop-in and drop-out at any time.
- Pack-set verification: a joining peer must have the same pack ids, versions, and content hashes as the host, or the join is refused with a readable reason.
- Authority model: each peer owns its own character and the vehicle it drives; the host owns the world (traffic, pedestrians, mission state, tone mode). Documented in `design.md` and required of every later gameplay proposal by AGENTS.md.
- Replication of players and their vehicles with interpolation; world entities replicated with relevance filtering (only what is near some player).
- Session-wide tone mode is chosen by the host (see `add-content-modes`).
- **Not in this change:** internet relay or NAT punchthrough, voice chat, PvP rules, dedicated servers, saves for multiplayer sessions.

## Impact
- Affected specs: `coop-session` (new). Later proposals for player, vehicles, traffic, pedestrians, and missions must state their authority model (AGENTS.md rule).
- Affected code: `game/core/net/` (new), `game/actors/` (players and vehicles become peer-owned), `game/world/` (streaming must keep chunks loaded around every player on the host), `game/ui/` (lobby).
- Performance: the host simulates a bubble of city life around every player. On a Steam Deck host this is the main risk; see `design.md`.
- Cost: no paid services. Internet play beyond direct IP may need a relay; that is a separate decision for the human.
