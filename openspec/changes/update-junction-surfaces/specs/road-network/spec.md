## ADDED Requirements

### Requirement: Junction Surfaces Cover Their Arms
Every junction with three or more arms SHALL have a surface polygon that the trimmed arms meet, with no curb inside it and no terrain showing above it.

#### Scenario: A junction that used to be a point
- **WHEN** the player drives through a junction the human reported as acting like a point
- **THEN** the roads meet at a junction surface, lane lines stop at its edge, and traffic turns across it

#### Scenario: A road running straight through a T
- **WHEN** a side road meets a road that runs straight on past it (issue #79)
- **THEN** the junction surface follows the through road's far edge, with no bulge into the grass and no notch back across the road

#### Scenario: A road dividing into carriageways
- **WHEN** a two-way road divides into two one-way carriageways at a node (issue #78)
- **THEN** each carriageway starts on its own side of the two-way road and the surface between them keeps the road's full width
