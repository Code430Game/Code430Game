## ADDED Requirements

### Requirement: Weapon Damage To Traffic
Traffic cars SHALL accumulate damage from impacts shown as a body tint by impact kind, SHALL stop and stay put past a damage threshold, and SHALL lose a tyre only to a lethal impact.

#### Scenario: Painted car
- **WHEN** a traffic car is hit by paintballs in `clean`
- **THEN** its body shows paint smears and it keeps driving until the damage threshold

#### Scenario: Tyre shot
- **WHEN** a tyre is hit by a bullet in `gritty`
- **THEN** the car pulls to a stop within a second and rests
