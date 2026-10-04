## ADDED Requirements

### Requirement: Vehicle Class Mix
Traffic SHALL spawn vehicles of several body classes with weights from the catalogue scaled by road class group and time of day, draw each class through its own MultiMesh per LOD with LOD chosen by distance to the nearest player, and replicate the class in snapshots.

#### Scenario: Day and night mix
- **WHEN** traffic is sampled at noon and at 22:00 on an arterial
- **THEN** vans and box trucks are more common at noon and taxis more common at 22:00

#### Scenario: Far cars use the low LOD
- **WHEN** a traffic car is beyond the preset's LOD0 distance from every player
- **THEN** it is drawn from the LOD1 MultiMesh and switches to LOD0 as a player approaches

### Requirement: Traffic Cars Give Way Physically
A traffic car struck by or pressed against a player's vehicle SHALL respond as a body with its class's mass: a frozen traffic body SHALL never meet a vehicle in contact, and no vehicle SHALL be separated from traffic at more than a configured speed.

#### Scenario: Rear-ending traffic
- **WHEN** the player's car hits a stopped traffic sedan from behind at 50 km/h
- **THEN** both cars move on with momentum shared between them, and the player's car is not stopped dead

#### Scenario: Wedged between two cars
- **WHEN** the player's car is pressed between two traffic cars
- **THEN** no car leaves the contact faster than the configured separation cap, and nothing is flung across the map
