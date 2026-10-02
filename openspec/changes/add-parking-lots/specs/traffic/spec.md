## ADDED Requirements

### Requirement: Parking-Only Lanes
Lane paths derived from edges of class `parking` SHALL be flagged parking-only: traffic SHALL never spawn on or route into them, buses SHALL never use them, and the player SHALL drive them freely.

#### Scenario: Car at a driveway
- **WHEN** a traffic car reaches a junction where one exit is a driveway and another is a street
- **THEN** the car takes the street

#### Scenario: Player into a lot
- **WHEN** the player turns from a street into a parking aisle
- **THEN** the car drives in with collision and markings as on any road
