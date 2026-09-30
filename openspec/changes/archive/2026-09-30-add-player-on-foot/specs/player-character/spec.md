## ADDED Requirements

### Requirement: On-Foot Movement
The game SHALL provide a player character that walks, runs, and jumps on road and terrain meshes using a gamepad alone, with camera-relative movement.

#### Scenario: Walk up a shoulder
- **WHEN** the player pushes the left stick toward a 20 degree slope
- **THEN** the character walks up it without sliding back

#### Scenario: Run
- **WHEN** the player holds sprint while moving
- **THEN** the character moves at the run speed from the config resource

### Requirement: Third-Person Camera
The on-foot camera SHALL orbit with the right stick and SHALL NOT clip through terrain or roads.

#### Scenario: Camera against a wall
- **WHEN** terrain is closer behind the character than the camera distance
- **THEN** the camera moves in front of the terrain instead of through it

### Requirement: Vehicle Entry And Exit
The player SHALL enter a nearby vehicle with the interact action and exit it again, with the camera and input following the player.

#### Scenario: Enter
- **WHEN** the character stands within 2.5 m of the car and presses interact
- **THEN** the player is driving the car within 0.5 s and the chase camera is active

#### Scenario: Exit while stopped
- **WHEN** the player presses interact in a car moving slower than 5 m/s
- **THEN** the character stands beside the driver's door on solid ground and the on-foot camera is active

#### Scenario: Exit refused at speed
- **WHEN** the player presses interact in a car moving faster than 5 m/s
- **THEN** the player stays in the car

### Requirement: Player Registry
Players SHALL be registered by peer id in a `Players` autoload, and no gameplay code SHALL assume a single global player.

#### Scenario: Local player lookup
- **WHEN** the testbed starts single-player
- **THEN** `Players.local()` returns the spawned character and `Players.all()` has one entry keyed by peer id 1

### Requirement: Config Resource
Movement, camera, and entry tunables SHALL live in an exported config resource, not in code constants.

#### Scenario: Change run speed
- **WHEN** a designer edits the run speed in the config resource
- **THEN** the character runs at the new speed without any code change
