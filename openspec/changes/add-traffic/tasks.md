## 0. Preconditions
- [x] 0.1 Human approves the proposal (2026-09-30)

## 1. Lane paths
- [x] 1.1 `lane_paths.gd`: lane centrelines per edge from lane counts and width; tests on synthetic edges
- [x] 1.2 Junction connections with turn curves, legal turns only; tests on a four-way cross and a one-way pair

## 2. Agents
- [x] 2.1 `traffic_car.tscn`: kinematic follower with placeholder box, colours, speed control, following distance
- [x] 2.2 Junction yielding with a simple first-in priority; tests with two agents
- [x] 2.3 Hit response: switch to physics briefly, then freeze

## 3. Manager
- [x] 3.1 Spawn/despawn around players by radius and class density; active cap in config
- [x] 3.2 Reduced-rate simulation for distant agents
- [x] 3.3 Debug overlay of lane paths and agent states

## 4. Verification
- [x] 4.1 Deck: 150 agents downtown, measured render and script time recorded (Steam Deck, deck preset, Bank Street, 150 agents: GPU 6.0 ms, render CPU 1.5 ms, physics process incl. traffic 5 to 8 ms, frame p99 9.7 ms; before the MultiMesh/pooled-body refactor traffic alone cost 39 ms)
- [ ] 4.2 **Stop: human drives in traffic on the Deck**
