# Change: Pedestrians on the sidewalks

**Status: proposed 2026-09-30 (queue item 3, approved in conversation: "lets build the next couple items").**

## Why
Traffic made the streets move; the sidewalks are still empty. People walking the sidewalks,
crossing at crossings and reacting to the player are the second half of a city that feels
inhabited, and the on-foot game has nobody to bump into.

## What Changes
- **Walk graph** from the pack's pedestrian ways: sidewalks, footways, paths, crossings and
  pedestrian streets joined where their ends meet. Steps are walkable; covered ways are not
  used (they are not drawn).
- **Pedestrian agents**: plain data, like traffic. Each walks a way at its own pace with a
  lateral offset inside the ribbon, picks a connected way at the end (preferring to keep
  going), turns around at dead ends, and stops when a player is right in front of it.
- **Rendering and bodies**: one MultiMesh draws them all (placeholder capsules in a few
  colours); a small pool of physics bodies follows the ones nearest the players so cars can
  hit them. A hit pedestrian tumbles as a rigid body, then lies still and is removed later.
- **Population** around players by radius with a cap, reduced-rate simulation when far,
  host-owned per the co-op readiness rule.
- **Not in this change:** animation, faces or clothing, dialogue, panic or fleeing, police,
  pedestrians using crossings with traffic yielding, tone-mode content.

## Impact
- Affected specs: `pedestrians` (new).
- Affected code: `game/world/pedestrians/` (new: walk graph, agent, body, manager, config),
  `play_testbed.gd` (`--peds=N`), tests.
- Performance: budgeted like traffic; measured on the Deck with 120 pedestrians near the player.
