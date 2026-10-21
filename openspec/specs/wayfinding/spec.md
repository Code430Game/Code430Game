# wayfinding Specification

## Purpose
Knowing where you are: the full-screen overview map and the corner minimap, both drawn from the road graph and the map pack.

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

### Requirement: Parks On Maps
The overview map and minimap SHALL fill park, grass and wooded areas green under the roads and above the building fill.

#### Scenario: Map over the canal
- **WHEN** the map is open over Confederation Park
- **THEN** the park shows as a green fill with the roads drawn over it

### Requirement: Map Legend And Places
The full map SHALL show a legend of the kinds of places in the pack, each as its icon and name, and SHALL let the player open a kind to list its places with real street addresses (or the nearest street when the data has none), then pick one to centre the map on it, going back a level with B.

#### Scenario: Finding a police station
- **WHEN** the player opens the map, selects Police in the legend and picks the first place
- **THEN** the map centres on that police station and highlights it, and the list showed its name and street address

#### Scenario: A place with no address tags
- **WHEN** a service place in the OSM data has no address tags
- **THEN** its list entry reads "on" followed by the nearest street's name
