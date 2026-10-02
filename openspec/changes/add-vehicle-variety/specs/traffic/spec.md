## ADDED Requirements

### Requirement: Vehicle Class Mix
Traffic SHALL spawn vehicles of several body classes with weights from the catalogue scaled by road class group and time of day, draw each class through its own MultiMesh per LOD with LOD chosen by distance to the nearest player, and replicate the class in snapshots.

#### Scenario: Day and night mix
- **WHEN** traffic is sampled at noon and at 22:00 on an arterial
- **THEN** vans and box trucks are more common at noon and taxis more common at 22:00

#### Scenario: Far cars use the low LOD
- **WHEN** a traffic car is beyond the preset's LOD0 distance from every player
- **THEN** it is drawn from the LOD1 MultiMesh and switches to LOD0 as a player approaches
