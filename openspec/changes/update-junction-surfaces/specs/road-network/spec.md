## ADDED Requirements

### Requirement: Junction Surfaces Cover Their Arms
Every junction with three or more arms SHALL have a surface polygon that the trimmed arms meet, with no curb inside it and no terrain showing above it.

#### Scenario: A junction that used to be a point
- **WHEN** the player drives through a junction the human reported as acting like a point
- **THEN** the roads meet at a junction surface, lane lines stop at its edge, and traffic turns across it
