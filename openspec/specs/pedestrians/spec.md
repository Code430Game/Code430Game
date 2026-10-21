# pedestrians Specification

## Purpose
People walking the city's sidewalks, crossings and pedestrian streets around the players: how they find their way, how they are drawn and animated as a crowd, and how they fall when a vehicle (or anything else that calls `knock_down`) hits them.

## Requirements

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
A pedestrian struck by a vehicle SHALL fall as a ragdoll whose limbs move freely within joint limits, then lie still where it came to rest, and SHALL be removed after a configured time. The vehicle SHALL feel configured resistance from the hit but SHALL NOT be stopped as if by a fixed obstacle; a walking pedestrian SHALL never present an immovable body to a vehicle.

#### Scenario: Struck
- **WHEN** the player's car hits a pedestrian
- **THEN** the pedestrian is thrown as a ragdoll, stops moving after the physics window, and disappears after the removal time

#### Scenario: Car keeps going
- **WHEN** the player's car hits a pedestrian at 50 km/h on flat ground
- **THEN** the car loses a configured amount of speed (a noticeable bump, about 5 to 8 km/h more than coasting) and keeps moving, and the pedestrian is thrown forward faster than walking pace

#### Scenario: Limbs flop
- **WHEN** a pedestrian is thrown
- **THEN** its arms, legs and head move relative to its torso during the fall

#### Scenario: Many hits at once
- **WHEN** a pedestrian is hit while every ragdoll is in use
- **THEN** the oldest downed ragdoll is recycled for the new hit

#### Scenario: Bumped on foot
- **WHEN** a player on foot walks into a pedestrian
- **THEN** the player is blocked by the pedestrian as before and the pedestrian is not knocked down

### Requirement: Population Around Players
Pedestrians SHALL spawn out of view within a configured radius of each player on walkable ways and despawn beyond a larger radius, under a configured cap, with reduced-rate simulation when far.

#### Scenario: Deck budget
- **WHEN** 120 pedestrians are active near the player on the Steam Deck
- **THEN** measured render time stays under the 33.3 ms floor and simulation cost is reported

### Requirement: Walking Animation
Pedestrians SHALL swing their arms and legs with the same walk cycle as the player, with the stride phase following distance walked and the cycle blending to a standing pose while they wait, while the crowd stays drawn in one draw call per body pool.

#### Scenario: Walking
- **WHEN** a pedestrian walks along a sidewalk
- **THEN** its legs and arms swing in opposition, one full cycle per stride length walked

#### Scenario: Waiting at a kerb
- **WHEN** a pedestrian waits for a crossing or for a player ahead
- **THEN** its limbs settle to the standing pose within half a second

#### Scenario: Crowd cost
- **WHEN** 120 pedestrians walk near the player
- **THEN** each body pool is still one MultiMesh draw and no per-person skeleton is created

### Requirement: Reaction To Weapons
A pedestrian struck by a lethal impact SHALL go down as if hit by a car, with blood only when the mode allows gore; one struck by a non-lethal impact SHALL be marked and flee, never going down; and pedestrians within earshot of gunfire SHALL flee in every mode.

#### Scenario: Paintball in clean
- **WHEN** a pedestrian is hit by a paintball
- **THEN** its body shows the paint colour and it runs off for the flee time, then walks again

#### Scenario: Shot in gritty
- **WHEN** a pedestrian is shot in `gritty`
- **THEN** it is thrown, lies still and is removed after the removal time, with a blood decal

#### Scenario: Gunfire nearby
- **WHEN** a gun fires within the earshot radius of walking pedestrians
- **THEN** they flee away from the shot
