## ADDED Requirements

### Requirement: Underpasses
A covered pedestrian way that joins open ways SHALL be built as a passage the player can walk through: a floor with clearance under whatever covers it, walls, a ceiling, portals, and approach ramps on the joined ways, with the terrain cut to match. A covered way with nothing modelled above it SHALL be drawn as an ordinary path.

#### Scenario: Path under a road
- **WHEN** a covered footway passes under a road 10 m wide and joins sidewalks at both ends
- **THEN** the player walks down a ramp, through a passage at least 3.4 m below the road surface, and up the other side without falling through or hitting the terrain

#### Scenario: Path under a bridge
- **WHEN** a covered path runs on the carved ground under a bridge deck
- **THEN** it is drawn as a plain path at ground level and nothing is dug
