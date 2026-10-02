## MODIFIED Requirements

### Requirement: Underpasses
A covered pedestrian way that joins open ways SHALL be built as a passage the player can walk through: a floor with clearance under whatever covers it, walls, a ceiling, portals, and approach ramps on the joined ways, with the terrain cut to match. A covered way with nothing modelled above it SHALL be drawn as an ordinary path. Each passage SHALL be lit by an emissive ceiling strip plus a preset-declared number of point lights, SHALL have a drainage grate and puddle at its low point, and its approach trenches SHALL have retaining walls where the cut is deeper than 0.4 m.

#### Scenario: Path under a road
- **WHEN** a covered footway passes under a road 10 m wide and joins sidewalks at both ends
- **THEN** the player walks down a ramp, through a passage at least 3.4 m below the road surface, and up the other side without falling through or hitting the terrain

#### Scenario: Path under a bridge
- **WHEN** a covered path runs on the carved ground under a bridge deck
- **THEN** it is drawn as a plain path at ground level and nothing is dug

#### Scenario: Lit at night
- **WHEN** the player walks through a passage at midnight on the deck preset
- **THEN** the ceiling strip glows and at most two point lights light the walls, and the passage is readable without headlights

#### Scenario: Trench walls
- **WHEN** an approach ramp cuts 1.5 m into the terrain
- **THEN** concrete retaining walls with a coping run along both sides of the cut
