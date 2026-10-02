## ADDED Requirements

### Requirement: Car Radio
The game SHALL play chip-style music synthesised at runtime from note data on a radio that runs while a player drives, with stations defined as tone-tagged content that packs can extend, a station cycle control, a remembered station, and a Music bus volume.

#### Scenario: Enter a car
- **WHEN** a player enters a car with a station remembered
- **THEN** that station plays, its name and tagline show briefly, and it pauses when the player gets out

#### Scenario: Cycle stations
- **WHEN** the player presses the radio control while driving
- **THEN** the next station in the cycle plays, Off being one entry, and the choice is saved

#### Scenario: Pack station
- **WHEN** a loaded pack ships a station file
- **THEN** its stations join the cycle after the base ones and its tracks play from their note data

#### Scenario: Tone variant
- **WHEN** the active mode is `dystopia` and a station has a dystopia variant
- **THEN** that variant's name, tagline and track list are used, and in `clean` the fallback is used

#### Scenario: Deck budget
- **WHEN** the radio plays on the Steam Deck
- **THEN** its generator fill stays within the existing audio cost and the frame average is unchanged within noise
