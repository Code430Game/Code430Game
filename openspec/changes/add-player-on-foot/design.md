## Context
Godot 4's `CharacterBody3D` with `move_and_slide` handles walking on the generated road and terrain trimeshes. The car is a `VehicleBody3D`; entering means parenting control, not the body. The co-op proposal (`add-coop-multiplayer`) requires every gameplay system to state who owns what.

## Goals / Non-Goals
- Goals: responsive on-foot movement on a controller; entering and leaving the car without a cutscene; a camera that never clips through terrain; code that works for N players even though only one exists.
- Non-Goals: animation quality, combat, physics-based ragdoll, ladders, water swimming (you walk on the river bed for now, which is a later fix).

## Decisions
- **Body**: `CharacterBody3D`, capsule 0.5 m radius, 1.8 m tall, `floor_max_angle` 50 degrees, snap to floor, walk 2.5 m/s, run 6 m/s, jump 1.2 m, gravity from project settings. Tunables in `player_config.tres` (a Resource with exported fields, editable in the editor, no magic numbers in code).
- **Movement**: camera-relative on the xz plane; the body turns toward the movement direction at a limited yaw rate so it does not snap.
- **Camera**: an orbit camera on a `SpringArm3D` (collision-aware) at 3.5 m; right stick orbits, left trigger is unused on foot. When in a car the existing `ChaseCamera` takes over; the switch crossfades position over 0.3 s.
- **Entering a vehicle**: an `Area3D` on the character finds `VehicleBody3D` nodes with a `Seat` marker within 2.5 m; the HUD shows "Y enter". On enter: the character is hidden and disabled, its transform is parented to the seat, the car's `driver` is set to the player, and input routes to the car. On exit: the car's input is cleared, the character is placed 1.5 m beside the driver's door on the ground (raycast down), and re-enabled. If the car is moving faster than 5 m/s, exit is refused.
- **Ownership**: `Players` autoload: `register(peer_id, node)`, `local() -> Player`, `all()`. The car gets `driver_peer_id`. The testbed spawns the local player through the registry and never holds a `_car` field of its own anymore.
- **Input**: existing actions (`move_*`, `look_*`, `sprint`, `jump`, `interact`). In a car, `move_*` steers and the triggers drive, as now.
- **Testbed**: `play_testbed.tscn` starts on foot next to the car; `--drive` starts inside it for the benchmark.

## Alternatives considered
- RigidBody character: harder to control, worse on stairs and curbs. Rejected.
- Physically parenting the character under the car: fights the physics server. Rejected in favour of hide-and-attach.

## Risks / Trade-offs
- Trimesh terrain at 8 m LOD1 collision has visible steps for a walking character. Mitigation: build collision from terrain LOD0 within 200 m of any player once streaming exists; for now accept it and note it.
- Exiting onto a slope can place the character inside terrain. Mitigation: raycast from the door position downward and upward, pick the first free spot, else refuse.

## Migration Plan
The drive testbed is renamed; the `--benchmark` and screenshot flags keep working with `--drive`.

## Open Questions
- Third-person only, or also a first-person toggle? (Recommended: third-person only for now.)
- Should the car keep its engine running when empty so it can roll away? (Recommended: yes, it is funnier and simpler.)
