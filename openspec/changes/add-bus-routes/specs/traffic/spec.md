## MODIFIED Requirements

### Requirement: Buses And Reserved Lanes
Lanes reserved for buses in the map data SHALL be marked and painted, cars SHALL never use them, and buses SHALL run numbered routes from the map data on a headway, following each route's edges, stopping only at its stops, turning at the terminus, showing the route number on a destination sign, and rejoining the route or roaming the larger roads when forced off it; streets without routes keep a share of free-roaming buses.

#### Scenario: Car at a bus-only street
- **WHEN** a car reaches a junction where one exit is bus-only and another is open to cars
- **THEN** the car takes the open exit

#### Scenario: Bus on its route
- **WHEN** a route bus reaches a junction
- **THEN** it takes the exit on the route's next edge and passes stops that are not on its route

#### Scenario: Bus at a route stop
- **WHEN** a route bus reaches one of its stops
- **THEN** it stands for the dwell time and then drives on

#### Scenario: Served on arrival
- **WHEN** a player arrives at a route with a 6 minute headway
- **THEN** buses are already spaced along the route about 6 minutes apart

#### Scenario: Forced off route
- **WHEN** a route bus is hit and comes to rest off its route
- **THEN** after recovering it rejoins the route at the nearest route edge ahead, or roams if none is within reach

#### Scenario: Bus cannot be taken
- **WHEN** the player presses interact next to a bus
- **THEN** nothing happens; the player's vehicle is always a car

#### Scenario: Bus at a stop
- **WHEN** a bus on a lane with a stop reaches the stop
- **THEN** it stands for the dwell time and then drives on
