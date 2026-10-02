# traffic Specification

## Purpose
TBD - created by archiving change add-traffic. Update Purpose after archive.
## Requirements
### Requirement: Lane Paths
The game SHALL derive per-lane centrelines from the road graph, with forward lanes on the right of travel, and SHALL connect them through junctions with turn curves that respect one-way edges.

#### Scenario: One-way street
- **WHEN** an edge is one-way
- **THEN** no lane path runs against its direction and no turn enters it from its exit end

### Requirement: Traffic Agents
Traffic cars SHALL follow lane paths at or below the edge speed limit, keep a following distance to the car ahead, choose legal turns at junctions, and yield to cross traffic already in a junction.

#### Scenario: Following
- **WHEN** a traffic car approaches a slower car in its lane
- **THEN** it slows to hold at least the configured following distance and never overlaps it

#### Scenario: Junction priority
- **WHEN** two traffic cars reach the same junction from crossing roads
- **THEN** the second to arrive waits until the first has cleared the junction

### Requirement: Population Around Players
Traffic SHALL spawn out of view within a configured radius of every player at a density per road class and despawn beyond a larger radius, keeping the active count under a configured cap.

#### Scenario: Deck budget
- **WHEN** 150 agents are active near the player on the Steam Deck
- **THEN** measured render time stays under the 33.3 ms floor and simulation cost is reported

### Requirement: Collisions With Traffic
The player SHALL be able to collide with traffic cars; a hit car SHALL become a physics body briefly, then stop.

#### Scenario: Rear-end
- **WHEN** the player drives into the back of a traffic car
- **THEN** the traffic car is pushed as a rigid body and the player car decelerates

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

