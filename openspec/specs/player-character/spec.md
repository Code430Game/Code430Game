# player-character Specification

## Purpose
TBD - created by archiving change add-player-on-foot. Update Purpose after archive.
## Requirements
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

### Requirement: Character Profile
The player character's look SHALL be described by a profile (skin, hair, clothing colours, hat, height, build) that is random on first start so nothing blocks play, and the body built from it SHALL be worn by the on-foot player and by that player's replica on other peers.

#### Scenario: First start
- **WHEN** the game starts with no saved characters
- **THEN** the player spawns wearing a random profile, and that profile is saved as the last created character

#### Scenario: Co-op
- **WHEN** a guest with a saved character joins a host
- **THEN** the host sees the guest's body built from the guest's profile

### Requirement: Character Creator
The pause menu SHALL open a creator where the player adjusts each profile field with a controller, sees the result immediately, randomises, saves the body as a preset, loads or deletes a preset, and leaves with the body applied and stored as the last created character.

#### Scenario: Tweak and keep
- **WHEN** the player changes the top colour and presses Done
- **THEN** the on-foot body shows the new colour, and the next start loads the same body

#### Scenario: Presets
- **WHEN** the player saves a preset, randomises, then loads that preset
- **THEN** the body matches the saved preset

