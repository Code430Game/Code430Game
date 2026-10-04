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
- [ ] 3.3 Testbed `--ped-hit` scenario (car at 50 km/h, one pedestrian ahead, speed before/after logged); record the **before** hit on the Mac with `--write-movie` and keep the speeds; test that the scenario runs headless and reports both speeds
- [ ] 3.4 Walk cycle (#15): rest-pose pool meshes with bone id per vertex, `pedestrian_walk.gdshader`, per-agent phase/amount advanced by distance and written as instance custom data; tests: shader coefficients match `walk_pose`, GDScript mirror of the shader matches `bone_global`, phase follows distance, amount settles to 0 within 0.5 s of waiting, one MultiMesh per pool; Mac screenshot of walkers
- [ ] 3.5 No kinematic contact: walker on the pedestrian layer, player mask 7, vehicle sensor `Area3D` with hit speed threshold, explicit car impulse and hit tunables in config, hits go through `knock_down(agent, impulse, point)`; tests: car at 50 km/h keeps moving and loses the configured speed (within tolerance), person thrown faster than walking, player on foot still blocked and does not knock anyone down, traffic car triggers a hit
- [ ] 3.6 Reusable `CharacterRagdoll` in `game/actors/character/` (any profile; `begin`, `apply_impulse`, `settle`, `release`; no pedestrian, vehicle or weapon code inside) and a pedestrian pool of them, from `CharacterRig` with `PhysicalBone3D`s and joint limits (or the 6DOF fallback if Jolt misbehaves, noted here), takes over the hit person's look and pose, holds its final pose until removal, oldest downed recycled when busy, impulse lands on the bone nearest the hit point; tests: a knock-down at head height and one at knee height move different bones first, limbs move relative to the torso during a fall, the body settles within the physics window, pool recycling, removal returns the ragdoll, `CharacterRagdoll` tested on its own with no manager; replaces the tumbling capsule test
- [ ] 3.7 Record the **after** hit on the Mac with the same scenario; before/after recordings and speeds go in the PR

## 4. Verification
- [x] 4.1 Deck (2026-09-30, same run as streaming 3.1): 120 pedestrians plus 150 traffic agents, GPU 6.70 ms, render CPU 1.10 ms, physics process 7.71 ms (was 5.9 ms with traffic alone)
- [ ] 4.1b Deck rerun with the walk shader and a ragdoll in progress: 120 pedestrians plus traffic, GPU, render CPU and physics process against 4.1
- [ ] 4.2 **Stop: human walks and drives among pedestrians on the Deck** (now also: limbs swing, drive into people and compare the hit, closes #15)
