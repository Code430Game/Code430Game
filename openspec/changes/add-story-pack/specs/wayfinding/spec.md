## ADDED Requirements

### Requirement: Mission Markers
The minimap and the overview map SHALL show the active objective's position, clamped to the minimap edge when out of view, and the world SHALL show a marker at the objective visible from the preset's draw distance.

#### Scenario: Objective behind the player
- **WHEN** the active objective lies outside the minimap's view radius
- **THEN** its ring is drawn at the minimap edge in the objective's direction

#### Scenario: Objective in sight
- **WHEN** the player is within 600 m of the objective with a clear line of sight
- **THEN** a vertical marker is visible at the objective's position
