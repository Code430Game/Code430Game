# traffic Specification

## Purpose
Traffic on the city's lanes around the players: spawning by road and hour, following, junction and signal behaviour, buses, a mix of vehicle classes, and bodies that crash like cars rather than walls.

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

### Requirement: Junction Control From Data
The importer SHALL export a control type for every node (signals, stop, give way or none) from its OSM tags, and clustering SHALL keep a control present on any merged node.

#### Scenario: Signalised cluster
- **WHEN** one of the nodes merged into a junction cluster is tagged as traffic signals
- **THEN** the cluster node's control is signals

### Requirement: Signal Cycles
Each signalised junction SHALL run a two-phase cycle over its approach axes with green, amber and all-red intervals from config, offset per junction, and no two conflicting phases SHALL be green at once.

#### Scenario: Cross
- **WHEN** a four-way signalised junction runs
- **THEN** the north-south and east-west phases alternate and are never green together

### Requirement: Traffic Obeys Control
A traffic car approaching a red or amber signal SHALL stop at the junction's stop line and proceed on green; a car at a stop sign SHALL come to a full stop before entering the junction.

#### Scenario: Red light
- **WHEN** a traffic car reaches a junction whose phase for its approach is red
- **THEN** it stops before the stop line and moves on when the phase turns green

### Requirement: Signal Heads
Signalised junctions SHALL show a pole and head at each approach whose colour is the approach's current light.

#### Scenario: Visible state
- **WHEN** an approach's phase is green
- **THEN** its head shows green and the crossing approaches' heads show red

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

### Requirement: Parking-Only Lanes
Lane paths derived from edges of class `parking` SHALL be flagged parking-only: traffic SHALL never spawn on or route into them, buses SHALL never use them, and the player SHALL drive them freely.

#### Scenario: Car at a driveway
- **WHEN** a traffic car reaches a junction where one exit is a driveway and another is a street
- **THEN** the car takes the street

#### Scenario: Player into a lot
- **WHEN** the player turns from a street into a parking aisle
- **THEN** the car drives in with collision and markings as on any road
