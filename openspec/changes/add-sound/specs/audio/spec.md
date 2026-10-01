## ADDED Requirements

### Requirement: Synthesised Vehicle And City Sound
The game SHALL synthesise an engine voice whose pitch rises with speed and throttle, tyre roll that grows with speed, a city ambience scaled by nearby traffic, and an impact sound scaled by collision speed, without audio assets.

#### Scenario: Accelerating
- **WHEN** the player accelerates from rest
- **THEN** the engine pitch and tyre noise rise with speed

#### Scenario: Collision
- **WHEN** the player's car hits a wall at speed
- **THEN** an impact sound plays whose loudness grows with the impact speed

### Requirement: Mixer
Sound SHALL route through Master, SFX and Ambience buses with volumes in settings and a mute flag.

#### Scenario: Mute
- **WHEN** the game starts with `--mute`
- **THEN** nothing is audible
