## Context
Addendum of 2026-10-04 (see proposal): walk cycle for the crowd (#15), hits that don't stop
the car dead, ragdoll falls. Pedestrians today are 8 MultiMeshes of pre-posed `CharacterMesh`
bodies plus a pool of 16 frozen kinematic `PedestrianBody` capsules near the players. The
player is a `CharacterRig` (Skeleton3D, 11 bones, `CharacterMesh.walk_pose`).

## Goals / Non-Goals
- Goals: limbs swing at crowd cost (no per-person skeleton); a hit is a thump, not a wall;
  limbs flop when someone is thrown; Deck budget holds.
- Non-Goals: animation blending beyond walk/stand, getting up, client-side ragdolls, IK.

## Decisions
- **Shader walk cycle, not skeletons.** The pool meshes are built in the rest pose with the
  bone index per vertex in `CUSTOM0` (one float). `pedestrian_walk.gdshader` gets each bone's
  pivot (uniform array, per pool, from `CharacterMesh.bone_pivot` for that pool's profile) and
  rebuilds the chain hips → thigh → shin and spine → upper arm → forearm as rotations about X,
  using the same coefficients as `walk_pose`. `INSTANCE_CUSTOM.x` = phase, `.y` = amount. The
  agent keeps `phase` and `amount`, advanced like `CharacterRig.advance` (`STRIDE_M` 1.3, blend
  rate 6/s), and `_render` writes them with `set_instance_custom_data`. Normals rotate with
  their bone. Alternatives: a skinned mesh per person (120 skeletons, too costly on the Deck);
  vertex animation textures (a baking step for no gain over 11 rigid bones).
  `walk_pose` stays the one source of the cycle: a test checks that the shader's coefficients
  match it, and a GDScript mirror of the shader maths is checked against `bone_global` at a few
  phases.
- **No kinematic contact with vehicles.** The walker moves to physics layer 3 ("pedestrians").
  The player's mask goes from 3 to 7, so on foot you still bump into people; vehicles (layer and
  mask 1) never touch the walker. A child `Area3D` (capsule radius 0.3 m + 0.15 m, mask 1)
  reports vehicles: a `VehicleBody3D` or a `traffic` RigidBody3D closing at more than
  `hit_min_speed_mps` (1.5) triggers the hit, so there is no solver contact with an
  infinite-mass body. This replaces unfreezing the capsule, which the probe showed comes a
  frame too late.
- **Resistance is explicit and tunable.** On a hit the car gets an impulse against its motion,
  `hit_car_impulse_ns` (default 1200 N·s, about 3.6 km/h off a 1200 kg car), on top of the
  real contacts between the ragdoll's bones and the car (about 3 km/h at 50 km/h in the probe).
  The person's bones start with `car_velocity * hit_transfer` (default 0.9) plus
  `hit_lift_mps` (1.5) upward. Traffic cars are kinematic-driven agents: they get the person
  thrown but no impulse.
- **Ragdoll is a character component, not a pedestrian one.** `CharacterRagdoll`
  (`game/actors/character/character_ragdoll.gd`) works from any `CharacterProfile` and knows
  nothing about pedestrians, cars or weapons. Its API: `begin(profile, xform, pose, velocity)`,
  `apply_impulse(impulse, world_point)` (to the nearest bone, callable at any time while active),
  `settle()` (hold the pose, stop simulating), `release()`, plus `is_settled()` and a
  `settled` signal. Pedestrians keep a pool of them; the player, co-op players and later NPCs
  can use the same class (for example the player going down in `add-weapons-and-combat`).
  Callers decide when to fall and how hard; the ragdoll only does the physics.
- **Ragdoll from the player rig.** `character_ragdoll.tscn`: a `CharacterRig` with a
  `PhysicalBoneSimulator3D` and one `PhysicalBone3D` per bone (capsules sized from the profile,
  cone-twist joints at shoulders, hips and neck, hinge-like limits at elbows and knees, masses
  adding up to 75 kg). `PedestrianManager` builds a pool of `ragdoll_pool` (default 6) at setup. On a hit the
  pedestrian leaves its MultiMesh, and a ragdoll takes its profile and walk pose at the moment
  of impact, then simulates for `hit_physics_s`. At the end it copies the bones' global poses
  into the skeleton's poses, stops simulating, and stays as a still skinned mesh until removal.
  Busy pool: recycle the downed ragdoll with the least time left. Fallback, if `PhysicalBone3D`
  under Jolt misbehaves (joint explosions, tunnelling at speed): rigid limbs as `RigidBody3D`s
  joined by `Generic6DOFJoint3D`s that write their transforms into the same skeleton. Task 3.6
  decides on the Mac before the Deck run.
- **One knock-down entry point, ready for weapons.** The car sensor doesn't start the
  ragdoll itself. It calls `PedestrianManager.knock_down(agent, impulse, point)`, which picks a
  ragdoll and applies the impulse to the bone nearest `point`: a car takes the legs out, and a
  later shot to the head spins the body differently. `add-weapons-and-combat` sends lethal
  impacts here ("down as a car hit does") with no new fall code, and its co-op path
  (`report_shot`, resolved on the host) ends in the same call, as `report_hit` → `hit_near`
  does for cars. While someone is down, the ragdoll's bones are ordinary colliders, so shots
  and cars can still move the body. Two things are reserved for that change:
  `INSTANCE_CUSTOM.zw` stay free for its paint marks (the walk uses only `.xy`), and its
  raycasts and projectiles must include the pedestrian layer (3) in their mask, because the
  walker is no longer on layer 1.
- **Repeatable hit for recordings.** The hit lab scene (`scenes/ped_hit_lab.tscn`) puts the player's car on a straight
  road at 50 km/h with one pedestrian walking ahead, then logs the car's speed before and
  after. Recordings use Godot's `--write-movie` at a fixed fps, converted with ffmpeg. The
  "before" recording is taken from `main`'s behaviour (the shipped frozen body) with the same
  scenario.

## Risks / Trade-offs
- Ragdoll physics cost: about 10 bodies and joints per active ragdoll, at most 6 at once.
  Measured in the Deck benchmark with a hit in progress (task 4.1b).
- Shader drift from `walk_pose`: guarded by the coefficient test.
- A car fast enough to cross the sensor in one physics tick (above roughly 30 m/s): the
  sensor is checked by a shape cast along the car's motion as well as by overlap.

## Migration Plan
None: no saved data. Co-op snapshots are unchanged; clients run the walk phase locally from
movement distance.

## Open Questions
- Default resistance: tuned at the Deck gate. The config makes it a one-number change.
