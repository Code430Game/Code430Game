# wayfinding Specification

## Purpose
TBD - created by archiving change add-water-and-wayfinding. Update Purpose after archive.
## Requirements
### Requirement: Overview Map
The game SHALL provide a toggleable full-screen map rendered from the road graph and water polygons, centred on the player with a heading marker, zoomable with the triggers, usable with a controller alone.

#### Scenario: Open the map
- **WHEN** the player presses the map action while driving on Metcalfe Street
- **THEN** the game pauses and shows the map centred on the car, north up, with the car's heading and "Metcalfe Street" beside the marker

#### Scenario: Hover a road
- **WHEN** the player moves the map cursor over Bank Street with the right stick
- **THEN** Bank Street is highlighted on the map and its name is shown by the cursor

#### Scenario: Zoom
- **WHEN** the player holds the right trigger on the map screen
- **THEN** the map zooms in around the player marker, and the left trigger zooms out

#### Scenario: No per-frame cost while hidden
- **WHEN** the map is closed
- **THEN** no map rendering happens until it is opened again

### Requirement: Minimap
While driving, the HUD SHALL show a minimap: a crop of the overview map texture around the player, rotated to the car's heading, with no text, in both graphics presets.

#### Scenario: Turning
- **WHEN** the car turns 90 degrees to the right
- **THEN** the minimap rotates so the road ahead still points up

#### Scenario: Map open
- **WHEN** the overview map is open
- **THEN** the minimap is hidden

