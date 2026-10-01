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

## 4. Verification
- [x] 4.1 Deck (2026-09-30, same run as streaming 3.1): 120 pedestrians plus 150 traffic agents, GPU 6.70 ms, render CPU 1.10 ms, physics process 7.71 ms (was 5.9 ms with traffic alone)
- [ ] 4.2 **Stop: human walks and drives among pedestrians on the Deck**
