## ADDED Requirements

### Requirement: Traffic Yields To Players
A traffic car SHALL treat any player body ahead in its lane corridor, whether a vehicle or a person on foot, as a car to keep headway from, and SHALL stop behind it rather than pass through it.

#### Scenario: Stopped player car
- **WHEN** the player's car stands still in a traffic lane
- **THEN** the next traffic car in that lane slows and stops behind it with at least the minimum gap

#### Scenario: Person on foot
- **WHEN** a player on foot stands in a traffic lane
- **THEN** approaching traffic in that lane stops short of them

### Requirement: Recovery After A Hit
A traffic car that has been hit SHALL remain an obstacle to the cars behind it while stopped, and after the physics window SHALL resume driving on the nearest lane when it is within the configured reach and roughly aligned with it; otherwise it stays put. A stopped car SHALL release its physics body when no player is within the body radius.

#### Scenario: Queue behind a hit car
- **WHEN** a traffic car is hit and comes to rest in its lane
- **THEN** the cars behind it queue with headway instead of overlapping it

#### Scenario: Resume
- **WHEN** a hit car has come to rest within reach of a lane and facing along it
- **THEN** it rejoins that lane and drives on after the physics window

### Requirement: Taking A Traffic Car
A player SHALL be able to take a traffic car by interacting next to it when no player vehicle is nearer; the traffic car becomes a drivable vehicle in its colour and the player is placed in it.

#### Scenario: Take a car
- **WHEN** the player on foot presses interact within enter range of a traffic car
- **THEN** a drivable car replaces the traffic car at its position and colour, the traffic agent is removed, and the player is driving it
