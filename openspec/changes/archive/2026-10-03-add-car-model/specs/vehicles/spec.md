## ADDED Requirements

### Requirement: Car Body Mesh
The game SHALL build car bodies procedurally from a body profile with a cabin, wheel arches, head and tail lights, with body vertices left white so instance or material colour paints them while glass and lights keep their own colours.

#### Scenario: Traffic colours
- **WHEN** traffic draws cars through its MultiMesh with per-instance colours
- **THEN** each car's body shows its colour and its glass and lights do not

### Requirement: Shared Mesh
The player's car and traffic cars SHALL use the same generated mesh, and traffic draw calls SHALL not increase from using it.

#### Scenario: Taken car
- **WHEN** the player takes a traffic car
- **THEN** the drivable car shows the same body shape and colour as the traffic car it replaced
