# audio Specification

## Purpose
All of the game's sound is synthesised at runtime from code and note data, with no audio assets to license: the engine, tyres, impacts and city ambience, and the car radio's chip-music stations and talk radio, mixed through buses the player can set.

## Requirements

### Requirement: Synthesised Vehicle And City Sound
The game SHALL synthesise an engine voice whose pitch rises with speed and throttle, tyre roll that grows with speed, a city ambience scaled by nearby traffic, and an impact sound scaled by collision speed, without audio assets. The engine and tyre voices SHALL sound whenever a player drives, including after getting out and back in.

#### Scenario: Accelerating
- **WHEN** the player accelerates from rest
- **THEN** the engine pitch and tyre noise rise with speed

#### Scenario: Collision
- **WHEN** the player's car hits a wall at speed
- **THEN** an impact sound plays whose loudness grows with the impact speed

#### Scenario: Getting back in
- **WHEN** the player gets out of the car, walks away, and gets back in
- **THEN** the engine is audible again as soon as they are driving

### Requirement: Mixer
Sound SHALL route through Master, SFX and Ambience buses with volumes in settings and a mute flag.

#### Scenario: Mute
- **WHEN** the game starts with `--mute`
- **THEN** nothing is audible

### Requirement: Car Radio
The game SHALL play chip-style music synthesised at runtime from note data on a radio that runs while a player drives. It SHALL have stations, each a single seamless loop of 30 to 60 seconds composed for the game: a bright platformer piece, a racing piece, an overworld adventure piece, a dungeon piece and a talk-radio piece of chip babble, plus Off. Players SHALL cycle stations while driving, the last station SHALL be remembered, and the radio SHALL have its own Music volume. No station reuses another game's melodies, names or sounds.

#### Scenario: Enter a car
- **WHEN** a player gets into a car with a station remembered
- **THEN** that station plays, its name and tagline show briefly, and it pauses when the player gets out

#### Scenario: Cycle stations
- **WHEN** the player presses the radio control while driving
- **THEN** the next station in the cycle plays, Off being one entry, and the choice is saved

#### Scenario: Seamless loop
- **WHEN** a station's loop reaches its end
- **THEN** it continues from its start without a gap or click, and the loop is at least 30 seconds long

#### Scenario: Deck budget
- **WHEN** the radio plays on the Steam Deck
- **THEN** its generator fill stays within the existing audio cost and the frame average is unchanged within noise
