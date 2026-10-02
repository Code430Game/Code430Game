## ADDED Requirements

### Requirement: Animated Pedestrian Bodies
Pedestrians SHALL wear the character body at the level of detail matching their distance, SHALL animate the walk cycle in step with their own speed through per-instance data rather than per-agent skeletons, and SHALL vary in colour per instance beyond the number of body pools, within the Deck draw-call and triangle budget stated in the change.

#### Scenario: Crowd walks
- **WHEN** 120 pedestrians are active near the player
- **THEN** each one's limbs swing at its own stride and stop when it stops, with no more than three draw calls per body pool

#### Scenario: Far crowd is cheap
- **WHEN** a pedestrian is 200 m from every player
- **THEN** it is drawn with the lowest-detail body and no face or accessory geometry

#### Scenario: Variety
- **WHEN** two pedestrians share a body pool
- **THEN** they can still differ in skin and top colour
