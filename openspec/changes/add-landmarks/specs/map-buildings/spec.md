## ADDED Requirements

### Requirement: Landmark Models Replace Generated Buildings
A map pack SHALL be able to supply landmark models, as part lists or glTF, that replace named generated buildings, with their own collision, levels of detail and optional tone variants; the Ottawa pack SHALL supply Parliament's Centre Block with the Peace Tower and the Library of Parliament.

#### Scenario: Parliament Hill
- **WHEN** the player looks at Parliament Hill from Wellington Street
- **THEN** they see the Centre Block with the Peace Tower and the Library behind it, not generated boxes, and an open lawn in front

#### Scenario: A replaced building moves in the data
- **WHEN** a pack's landmark names a building id that the pack's buildings no longer contain
- **THEN** pack validation fails and names the missing id
