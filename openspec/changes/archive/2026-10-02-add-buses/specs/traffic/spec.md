## ADDED Requirements

### Requirement: Buses And Reserved Lanes
Lanes reserved for buses in the map data SHALL be marked and painted, cars SHALL never use them, and a share of traffic SHALL be buses that prefer reserved lanes, keep to the larger roads otherwise, stop briefly at bus stops, and keep a following distance that accounts for their length.

#### Scenario: Car at a bus-only street
- **WHEN** a car reaches a junction where one exit is bus-only and another is open to cars
- **THEN** the car takes the open exit

#### Scenario: Bus at a stop
- **WHEN** a bus on a lane with a stop reaches the stop
- **THEN** it stands for the dwell time and then drives on

#### Scenario: Bus cannot be taken
- **WHEN** the player presses interact next to a bus
- **THEN** nothing happens; the player's vehicle is always a car
