## ADDED Requirements

### Requirement: Host and Join
The game SHALL let a player host a session and let up to three other players join it over LAN or direct IP, using a controller alone.

#### Scenario: Fourth player joins
- **WHEN** a session has a host and two clients and a fourth player joins
- **THEN** the fourth player spawns in the world and all four see each other

#### Scenario: Fifth player refused
- **WHEN** a session already has four players and another player attempts to join
- **THEN** the join is refused with a message stating the session is full

### Requirement: Pack Set Verification
A joining peer SHALL be admitted only if its enabled packs match the host's by id, version, and content hash.

#### Scenario: Mismatched pack version
- **WHEN** a joining peer has a different version of a map pack than the host
- **THEN** the join is refused and the message names the pack and both versions

### Requirement: Peer-Owned Player Bodies
Each peer SHALL be authoritative over its own character and the vehicle it drives, and other peers SHALL see interpolated state.

#### Scenario: Entering a vehicle
- **WHEN** a client enters the driver's seat of a vehicle
- **THEN** authority over that vehicle transfers to that client and its movement is driven by that client's input

### Requirement: Host-Owned World
The host SHALL be authoritative over traffic, pedestrians, mission state, world time, weather, and the session tone mode.

#### Scenario: Tone mode on join
- **WHEN** a client joins a session whose host selected the `clean` tone mode
- **THEN** the client runs in `clean` mode for the duration of the session and cannot change it

### Requirement: Relevance-Filtered Replication
The host SHALL replicate world entities to a peer only when they are within that peer's configured interest radius for the entity's class.

#### Scenario: Distant traffic
- **WHEN** a traffic vehicle is farther from a client than the traffic interest radius
- **THEN** the host sends that client no state for that vehicle

### Requirement: Drop-In and Drop-Out
Players SHALL be able to join and leave at any time without ending the session or rolling back mission state.

#### Scenario: Driver disconnects
- **WHEN** a client disconnects while driving a vehicle with a passenger
- **THEN** the vehicle remains in the world under host authority and the passenger stays seated

### Requirement: Host Performance Budget
When a Steam Deck hosts, the game SHALL scale per-player simulation bubbles so that the `deck` frame-time floor is held with two connected players.

#### Scenario: Deck hosting two players
- **WHEN** a Steam Deck hosts a session with two clients driving in different districts
- **THEN** host frame time stays at or under 33.3 ms
