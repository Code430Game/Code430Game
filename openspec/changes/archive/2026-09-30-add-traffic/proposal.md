# Change: Add AI traffic on the road graph (Phase 3, part 1)

**Status: APPROVED by the human on 2026-09-30.**

## Why
The city is legible and fun to drive, and it is empty. Cars that follow lanes, respect one-ways, and stop for each other are what make a street feel like a street. The road graph already carries lanes, one-way direction, and speed limits, so traffic is mostly simulation, not data.

## What Changes
- **Lane paths**: per-edge lane centrelines derived from the graph (offset by lane index, forward lanes on the right), joined through junctions with simple turn curves. Computed at load and cached with the chunk data.
- **Traffic agents**: lightweight kinematic cars (not VehicleBody3D) that follow lane paths at the edge speed limit, pick a random legal turn at each junction, keep a following distance to the car ahead in the same lane, and yield at junctions with a simple priority rule (first in, main road first). Placeholder box models in several colours.
- **Population control**: agents spawn out of view within a radius of each player and despawn beyond it (config), with a density target per road class so the highway is busy and side streets are quiet. Host-owned and relevance-filtered per the co-op readiness rule.
- **Player interaction**: traffic cars are solid bodies the player can hit; hit cars switch from kinematic to physics for a few seconds, then stop and stay put. No damage model.
- **Debug view**: lane paths and agent states drawn on the road-graph overlay.
- **Not in this change:** pedestrians, traffic lights, parking, honking, police, sirens, damage, tone-mode content (traffic cars carry no descriptor-tagged content yet).

## Impact
- Affected specs: `traffic` (new).
- Affected code: `game/world/traffic/` (new: lane paths, agent, manager), `game/actors/vehicles/` (traffic car scene), `map_pack.gd` (lane path cache), debug view.
- Authority model: the host simulates all agents; clients would receive interpolated transforms (deferred to the co-op change).
- Performance: target 150 agents near the player on the Deck within budget; agents far from any player are simulated at a reduced rate. Deck GPU and CPU time recorded before and after.
