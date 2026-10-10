## ADDED Requirements

### Requirement: Vehicle Models From The Art Kit
Vehicle catalogue entries SHALL be able to name a kit model used for the drivable car, traffic and parked cars, with wheels and lights taken from named nodes and liveries applied as overrides, falling back to the generated body when no model is named.

#### Scenario: Traffic in kit models
- **WHEN** the player drives downtown after the vehicle stage
- **THEN** traffic, parked cars and the player's car are kit models, and police cars and ambulances carry their liveries
