## ADDED Requirements

### Requirement: Districts Played Together
The game SHALL play a set of map packs of one city as one map when they share an origin and projection and their borders, on the 256 m chunk grid, do not overlap. Each chunk SHALL be built from the district whose border contains it, and a set that breaks these rules SHALL be refused with a reason.

#### Scenario: Two districts at once
- **WHEN** Centretown and the Glebe are played together
- **THEN** chunks on each side of the border come from their own pack and the minimap shows both districts as one map

#### Scenario: A mismatched set
- **WHEN** a set includes a district with a different origin
- **THEN** the loader refuses the set and the Packs tab says why

### Requirement: Roads Across District Borders
Where two districts in play meet, roads that cross the border SHALL be joined into one road graph, without the edge roadblock, when their crossings match within 1 m and 15°; unmatched crossings SHALL keep their roadblock.

#### Scenario: Driving across the border
- **WHEN** a player drives along a street that crosses from Centretown into the Glebe
- **THEN** the road continues without a barrier or a step in the ground, and traffic follows the same street across
