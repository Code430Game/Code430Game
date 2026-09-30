## 1. Players as obstacles
- [x] 1.1 `TrafficManager.obstacles` (player bodies with a radius); `_gap_ahead` includes a player ahead in the lane corridor; test: an agent stops behind a stopped player car and behind a person on foot

## 2. Hit recovery
- [x] 2.1 Retired agents stay in the lane index at their last distance so followers queue; test
- [x] 2.2 After `hit_physics_s`, an agent near an aligned lane resumes driving on it; test
- [x] 2.3 Bodies released from retired agents beyond the body radius; on-foot player collides with traffic bodies; test

## 3. Taking a traffic car
- [x] 3.1 `TrafficManager.take_car(body) -> VehicleBody3D` spawns a placeholder car in the agent's colour and removes the agent; test
- [x] 3.2 Player interact falls back to the nearest traffic car within range; testbed wires it

## 4. Verification
- [ ] 4.1 Deck: measured render and physics time with 150 agents recorded
- [ ] 4.2 **Stop: human drives, walks in traffic and takes a car on the Deck**
