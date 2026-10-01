## ADDED Requirements

### Requirement: Walk Graph
The game SHALL derive a walk graph from the pack's pedestrian ways, joining ways whose ends meet, excluding covered ways.

#### Scenario: Corner
- **WHEN** two sidewalks end at the same point
- **THEN** a pedestrian reaching that end can continue onto the other sidewalk

### Requirement: Pedestrian Agents
Pedestrians SHALL walk the walk graph at individual speeds within the ribbon width, choose a connected way at each end, turn around at dead ends, and stop when a player stands directly ahead of them.

#### Scenario: Player in the way
- **WHEN** a player stands within two metres ahead of a walking pedestrian
- **THEN** the pedestrian stops until the way is clear

### Requirement: Hit By A Car
A pedestrian struck by a vehicle SHALL become a physics body briefly, then lie still where it came to rest, and SHALL be removed after a configured time.

#### Scenario: Struck
- **WHEN** the player's car hits a pedestrian
- **THEN** the pedestrian is thrown as a rigid body, stops moving after the physics window, and disappears after the removal time

### Requirement: Population Around Players
Pedestrians SHALL spawn out of view within a configured radius of each player on walkable ways and despawn beyond a larger radius, under a configured cap, with reduced-rate simulation when far.

#### Scenario: Deck budget
- **WHEN** 120 pedestrians are active near the player on the Steam Deck
- **THEN** measured render time stays under the 33.3 ms floor and simulation cost is reported
