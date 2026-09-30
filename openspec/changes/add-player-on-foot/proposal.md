# Change: Add the on-foot player and vehicle entry (Phase 2)

**Status: PROPOSED 2026-09-30, awaiting the human's approval.** Next roadmap phase after roads. Written so the human can approve it while working on other things; nothing is implemented yet.

## Why
The city can be driven but not walked. Phase 2 in VISION.md is the player: on-foot movement, entering and leaving vehicles, a camera that works for both, controller-first. It is also the first gameplay system built under the co-op readiness rule, so its authority model sets the pattern for everything after it.

## What Changes
- **Player character**: a capsule-based `CharacterBody3D` with walk, run, and jump on terrain and road meshes, camera-relative movement, gravity, slope handling, and a placeholder mannequin mesh. Tunables in an exported config resource.
- **Third-person camera** for on-foot play with right-stick orbit, collision-aware zoom, and a smooth handover to the existing chase camera when entering a car.
- **Vehicle entry and exit**: walk up to the car and press Y to enter; Y again to exit at the driver's door. Ownership of the car's controls moves with the player. The car keeps rolling with nobody in it; parked cars stay where they are.
- **Player registry**: `Players` autoload holding players by slot with a local slot 0, no global "the player" singleton, per the AGENTS.md co-op rule. All spawn, camera, and HUD code goes through it.
- **Testbed**: the drive testbed becomes the play testbed; you start on foot beside the car on the Queensway shoulder. Minimap and map follow whichever body the player controls.
- **Not in this change:** animations beyond placeholder poses, climbing, swimming, weapons, NPCs, multiple vehicles to choose from, save games.

## Impact
- Affected specs: `player-character` (new). `wayfinding` gains no new requirement; its "player" becomes the registry's local player.
- Affected code: `game/actors/player/` (new), `game/core/players.gd` (new autoload), `game/actors/vehicles/` (seat and ownership), `game/scenes/drive_testbed.*` (renamed to `play_testbed`), input map (`interact` already exists).
- Authority model (co-op readiness): the player body and any vehicle they drive are owned by their peer; entry and exit are requests the host arbitrates when networking exists. The registry is keyed by peer id from day one.
- Tone modes: on-foot movement has no descriptor-tagged content. The mannequin is neutral.
- Performance: one character and one camera; negligible.
