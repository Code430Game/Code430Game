## 1. Walk graph
- [x] 1.1 `walk_graph.gd`: ways joined at shared ends, lengths, next-way choice; tests on synthetic ways

## 2. Agents
- [x] 2.1 `pedestrian.gd` + `pedestrian_manager.gd`: walking, turning, dead-end reversal, stop for a player ahead; tests
- [x] 2.2 `pedestrian_body.tscn`: pooled rigid body near players; hit by a car tumbles then lies still and is removed; test
- [x] 2.3 MultiMesh rendering, spawn/despawn by radius and cap, reduced rate when far; test

## 3. Integration
- [x] 3.1 Testbed `--peds=N`, anchors and obstacles from the players, benchmark line

## 3b. Crossings (2026-10-01)
- [x] 3.2 Crossings link to the road they span and the signalised junction they belong to; people wait at the kerb until that road's red, or for a 25 m gap at an uncontrolled crossing (30 s cap), and traffic keeps headway from anyone on a crossing; tests

## 3c. Walking limbs, softer hits, ragdoll falls (addendum 2026-10-04)
- [x] 3.3 Hit lab `scenes/ped_hit_lab.tscn` (a standalone scene instead of a testbed flag: a city street can't put a walker in the car's path on cue): flat road, one walker on a crossing timed to meet the player's car at 50 km/h, speeds logged; test runs it headless. **Before** (Mac, `--write-movie`): car 49.0 → 0.1 km/h (48.9 lost), person tips over in place, frozen mid-stride
- [x] 3.4 Walk cycle (#15): rest-pose pool meshes with bone id per vertex, `pedestrian_walk.gdshader`, per-agent phase/amount advanced by distance and written as instance custom data; tests: shader coefficients match `walk_pose`, GDScript mirror of the shader matches `bone_global`, phase follows distance, amount settles to 0 within 0.5 s of waiting, one MultiMesh per pool; Mac screenshot of walkers; done 2026-10-04: walk coefficients are named constants on `CharacterMesh`, phase stepping shared as `CharacterRig.step_walk`; co-op clients run the cycle from the speed between snapshots
- [x] 3.5 No kinematic contact: walker on the pedestrian layer, player mask 7, vehicle sensor `Area3D` with hit speed threshold, explicit car impulse and hit tunables in config, hits go through `knock_down(agent, impulse, point)`; tests: car at 50 km/h keeps moving and loses the configured speed (within tolerance), person thrown faster than walking, player on foot still blocked and does not knock anyone down, traffic car triggers a hit; done 2026-10-04: hit lab at 50 km/h, car 49.1 → 37.0 km/h (12.1 lost vs 6.8 coasting: 5.3 km/h for the hit), person thrown at 12.9 m/s; traffic cars now knock people down at all (they never could: their frozen bodies report zero velocity)
- [x] 3.6 Reusable `CharacterRagdoll` in `game/actors/character/` (any profile; `begin`, `apply_impulse`, `settle`, `release`; no pedestrian, vehicle or weapon code inside) and a pedestrian pool of them, from `CharacterRig` with `PhysicalBone3D`s and joint limits (or the 6DOF fallback if Jolt misbehaves, noted here), takes over the hit person's look and pose, holds its final pose until removal, oldest downed recycled when busy, impulse lands on the bone nearest the hit point; tests: a knock-down at head height and one at knee height move different bones first, limbs move relative to the torso during a fall, the body settles within the physics window, pool recycling, removal returns the ragdoll, `CharacterRagdoll` tested on its own with no manager; replaces the tumbling capsule test; done 2026-10-04: `PhysicalBone3D` behaves under Jolt (thrown at 12 m/s the body lands about 10 m on and settles within 2 s, joints stay within 12 cm, nothing sinks through the floor), so no 6DOF fallback. Bones collide with the world and vehicles but not with each other. The held pose is read from the physical bones: the skeleton's own global poses leave out the simulator, and holding those stood the body back up (caught by the test)
- [x] 3.7 Record the **after** hit on the Mac with the same scenario; before/after recordings and speeds go in the PR; done 2026-10-04 (both clips from the same camera; before from `main`'s code): before 49.1 → 0.2 km/h, person tips over in place at 2.7 m/s; after, coasting 49.1 → 37.0 km/h with the person thrown at 12.1 m/s (`--brake`: thrown about 15 m, car stops of its own accord)

## 4. Verification
- [x] 4.1 Deck (2026-09-30, same run as streaming 3.1): 120 pedestrians plus 150 traffic agents, GPU 6.70 ms, render CPU 1.10 ms, physics process 7.71 ms (was 5.9 ms with traffic alone)
- [ ] 4.1b Deck rerun with the walk shader and a ragdoll in progress: 120 pedestrians plus traffic, GPU, render CPU and physics process against 4.1
- [ ] 4.2 **Stop: human walks and drives among pedestrians on the Deck** (now also: limbs swing, drive into people and compare the hit, closes #15)
