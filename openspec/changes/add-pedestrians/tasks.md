## 1. Walk graph
- [x] 1.1 `walk_graph.gd`: ways joined at shared ends, lengths, next-way choice; tests on synthetic ways

## 2. Agents
- [x] 2.1 `pedestrian.gd` + `pedestrian_manager.gd`: walking, turning, dead-end reversal, stop for a player ahead; tests
- [x] 2.2 `pedestrian_body.tscn`: pooled rigid body near players; hit by a car tumbles then lies still and is removed; test
- [x] 2.3 MultiMesh rendering, spawn/despawn by radius and cap, reduced rate when far; test

## 3. Integration
- [x] 3.1 Testbed `--peds=N`, anchors and obstacles from the players, benchmark line

## 4. Verification
- [ ] 4.1 Deck: 120 pedestrians near the player, measured render and physics time recorded
- [ ] 4.2 **Stop: human walks and drives among pedestrians on the Deck**
