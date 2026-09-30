## ADDED Requirements

### Requirement: Road Name HUD
While driving, the HUD SHALL show the name and class of the road the player is on and the name of the next cross street ahead, updated at least four times per second.

#### Scenario: On a named road
- **WHEN** the car is within 20 m of an edge named "Metcalfe Street"
- **THEN** the HUD shows "Metcalfe Street"

#### Scenario: Unnamed road
- **WHEN** the nearest edge has no name
- **THEN** the HUD shows the road class instead, for example "motorway link"

### Requirement: Overview Map
The game SHALL provide a toggleable full-screen map rendered from the road graph and water polygons, centred on the player with a heading marker, zoomable with the triggers, usable with a controller alone.

#### Scenario: Open the map
- **WHEN** the player presses the map action while driving
- **THEN** the game pauses and shows the map centred on the car, north up, with the car's heading

#### Scenario: Zoom
- **WHEN** the player holds the right trigger on the map screen
- **THEN** the map zooms in around the player marker, and the left trigger zooms out

#### Scenario: No per-frame cost while hidden
- **WHEN** the map is closed
- **THEN** no map rendering happens until it is opened again
