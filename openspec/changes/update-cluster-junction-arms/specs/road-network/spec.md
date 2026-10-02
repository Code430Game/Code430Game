## MODIFIED Requirements

### Requirement: Drivable Generated Roads
The game SHALL generate road, junction, and terrain meshes with collision from the road graph, split into 256 m chunks with LODs. Where the importer has merged nearby junction nodes into one, each road SHALL keep its own straight line through the merged junction instead of bending to the junction centre, so parallel carriageways stay parallel in the meshes, the lane paths and the map.

#### Scenario: Drive across a chunk seam
- **WHEN** the placeholder car drives from one chunk to the next
- **THEN** there is no gap, step, or missing collision at the seam

#### Scenario: Deck performance
- **WHEN** the testbed runs on the `deck` preset on a Steam Deck
- **THEN** frame time stays at or under 33.3 ms while driving through the district

#### Scenario: Divided road through a merged junction
- **WHEN** two one-way carriageways of the same street pass through a merged junction node
- **THEN** their ribbons, edge lines and minimap lines run parallel through it without crossing, and traffic on either carriageway continues straight without steering toward the junction centre
