## ADDED Requirements

### Requirement: House Types
Houses SHALL be built as one of several house types chosen from their data (detached with a front gable, cottage, bungalow, semi-detached and terrace rows), with a front door facing the nearest street, a porch or stoop, framed windows and a height suited to the type.

#### Scenario: A residential street
- **WHEN** the player walks a street of detached houses
- **THEN** the houses vary in type and material, each has a front door and porch facing the street, and none is a tall plain box

#### Scenario: A terrace row
- **WHEN** a row of terrace houses is drawn
- **THEN** the units share party walls and a roof line, each with its own door and porch

### Requirement: Yards And Fences
The land around a house SHALL be drawn as a front lawn toward the street and a backyard behind it, with fences along shared backyard boundaries that never cross a driveway, path or road.

#### Scenario: Behind the houses
- **WHEN** the player looks over the backs of a row of detached houses
- **THEN** each has a fenced backyard separated from its neighbours'
