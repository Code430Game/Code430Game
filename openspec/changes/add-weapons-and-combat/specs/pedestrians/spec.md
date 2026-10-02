## ADDED Requirements

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
