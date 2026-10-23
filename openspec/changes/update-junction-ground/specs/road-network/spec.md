## ADDED Requirements

### Requirement: Road Edges Without Wheel Traps
The ground just past the edge of a ground-level road SHALL NOT sit more than 0.25 m below the road where nothing else (another road, a junction, a sidewalk or a path) covers it, except beside water, a retaining wall or a bridge. The ground under a junction SHALL follow the junction's surface, so that neither its arms' edges drop away nor terrain shows through it. A sidewalk SHALL NOT be lifted more than 0.5 m to meet the ground; where the ground stands higher, the ground SHALL be cut along the sidewalk instead.

#### Scenario: Leaving the road onto the grass
- **WHEN** the player drives a wheel off the edge of an ordinary street onto the grass beside it
- **THEN** the wheel rolls onto ground level with the road's edge and does not drop or stick

#### Scenario: A corner where a street climbs away from the junction
- **WHEN** two streets meet at a junction at different heights
- **THEN** neither street's edge drops away at the corner, and no grass shows through the junction surface

#### Scenario: A sidewalk beside an embankment
- **WHEN** a street's sidewalk runs beside a higher road's embankment, such as Metcalfe beside the 417
- **THEN** the sidewalk stays at the street's level and does not climb the embankment
