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
- **Not in this change:** faces or clothing, dialogue, panic or fleeing, police,
  pedestrians using crossings with traffic yielding, tone-mode content.

## Addendum 2026-10-04: walking limbs, softer hits, ragdoll falls
**Status: approved 2026-10-04 ("That sounds good ... the plan looks smart").** Added before the 4.2 Deck gate so a single
gate covers both: the human asked for it after first trying the build (issue #15, and "they
stop a vehicle pretty quick ... should provide resistance for sure but maybe we tweak it",
"I wonder if we added some rag doll falling").

- **Walk cycle (#15).** Pedestrians swing their arms and legs like the player. The crowd is
  still drawn by the 8 MultiMeshes, one draw each: the meshes are built in the rest pose with
  each vertex's bone stored in a custom channel, and a vertex shader applies the player's
  `CharacterMesh.walk_pose` per instance. Phase and amount come from `INSTANCE_CUSTOM`, which
  the manager writes next to the transform it already writes. Phase advances with distance
  walked, so feet don't slide, and the walk blends to standing while someone waits.
- **Hits stop the car far too hard: cause confirmed.** A headless probe (the player car at
  50 km/h into a `PedestrianBody` on flat ground) gives:

  | target | car before | lowest after | speed lost | person thrown |
  |---|---|---|---|---|
  | none (coasting) | 49.9 km/h | 43.6 km/h | 6.3 km/h | – |
  | shipped body | 49.9 km/h | **−0.3 km/h** | **50.2 km/h** | **0 m/s** |
  | free 75 kg body | 49.9 km/h | 40.4 km/h | 9.4 km/h | 7.9 m/s |

  The walking body is a frozen kinematic RigidBody3D, which the solver treats as infinite
  mass. `body_entered` (and so the unfreeze in `_on_body_hit`) only fires after that contact
  has already been solved, so the car stops dead and the person is barely moved. Fix: vehicles
  never touch the kinematic walker. It moves to its own physics layer that only people collide
  with, so you still bump into pedestrians on foot. A slightly larger sensor detects a vehicle
  closing at more than 1.5 m/s, and the person becomes a ragdoll there and then: the bones take
  the car's velocity scaled by a tunable transfer and the car gets a tunable resistance impulse.
  The aim is a noticeable thump (about 5–8 km/h lost at 50 km/h on top of coasting, tuned on the
  Deck), not a wall.
- **Ragdoll falls.** A small pool of ragdolls replaces the single tumbling capsule. Each is the
  player's `CharacterRig` skeleton (same 11 bones), built with the hit person's look and driven
  by `PhysicalBone3D`s with capsule shapes and joint limits, so limbs flop. After the physics
  window the pose is held and the simulation stops; the body lies there until removal as now.
  When every ragdoll is busy, the oldest downed one is recycled. Traffic cars trigger the same
  fall.
- **Not in the addendum:** limb flop on co-op clients (they see the host's downed transform,
  as today), injuries, blood, getting up again, crowd reactions to a hit.

## Impact
- Affected specs: `pedestrians` (new).
- Affected code: `game/world/pedestrians/` (new: walk graph, agent, body, manager, config),
  `play_testbed.gd` (`--peds=N`), tests.
- Performance: budgeted like traffic; measured on the Deck with 120 pedestrians near the player.
- Addendum: `character_mesh.gd` (bone id per vertex for the shader), new
  `pedestrian_walk.gdshader`, reusable `actors/character/character_ragdoll.gd/.tscn`, `pedestrian_body.gd/.tscn`
  (layer, sensor), `player.tscn` (mask gains the pedestrian layer), `pedestrian_config.json`
  (hit tunables), testbed `--ped-hit` scenario for repeatable recordings. The Deck benchmark is
  rerun with the walk shader and a hit in progress.
