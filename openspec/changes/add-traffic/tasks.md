## 0. Preconditions
- [ ] 0.1 Human approves the proposal

## 1. Lane paths
- [ ] 1.1 `lane_paths.gd`: lane centrelines per edge from lane counts and width; tests on synthetic edges
- [ ] 1.2 Junction connections with turn curves, legal turns only; tests on a four-way cross and a one-way pair

## 2. Agents
- [ ] 2.1 `traffic_car.tscn`: kinematic follower with placeholder box, colours, speed control, following distance
- [ ] 2.2 Junction yielding with a simple first-in priority; tests with two agents
- [ ] 2.3 Hit response: switch to physics briefly, then freeze

## 3. Manager
- [ ] 3.1 Spawn/despawn around players by radius and class density; active cap in config
- [ ] 3.2 Reduced-rate simulation for distant agents
- [ ] 3.3 Debug overlay of lane paths and agent states

## 4. Verification
- [ ] 4.1 Deck: 150 agents downtown, measured render and script time recorded
- [ ] 4.2 **Stop: human drives in traffic on the Deck**
