## ADDED Requirements

### Requirement: Emergency Service Places
The pack SHALL list police stations, hospitals, fire stations, ambulance posts and helipads from OpenStreetMap with a kind, a name, a position and the nearest road node, keeping private and campus security apart from police; the maps SHALL show them with an icon per kind.

#### Scenario: Police headquarters on the map
- **WHEN** the player opens the map over Elgin Street
- **THEN** a police badge marks the Ottawa Police Headquarters and names it on hover

### Requirement: Respawn At Services
A busted player SHALL respawn outside the nearest police station and a wasted player outside the nearest hospital, falling back to the spawn point when the pack has none.

#### Scenario: Wasted near Saint-Vincent
- **WHEN** the player is wasted nearer Saint-Vincent Hospital than any other hospital
- **THEN** they respawn on the road outside Saint-Vincent Hospital
