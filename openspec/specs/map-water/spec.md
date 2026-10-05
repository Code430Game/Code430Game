# map-water Specification

## Purpose
Rivers, the canal and other water from OSM polygons: carried in the map pack, drawn as water surfaces with a floor to wade on, and meeting the land at a shoreline.
## Requirements
### Requirement: Water Polygons In Map Packs
The import tool SHALL write `water.v0.json` containing every OpenStreetMap water area intersecting the bbox, clipped to the bbox, triangulated, with a surface height and the OSM id and name.

#### Scenario: River relation crossing the bbox
- **WHEN** a `natural=water` multipolygon relation extends beyond the bbox
- **THEN** its rings are assembled from full member geometry and the clipped part inside the bbox is written

#### Scenario: Unassemblable relation
- **WHEN** a water relation's member ways do not form closed rings
- **THEN** it is skipped and the validation report lists its relation id

### Requirement: Water Rendering
The game SHALL draw each water polygon as a flat surface at its recorded height in both graphics presets, chunked on the 256 m grid.

#### Scenario: Ottawa River visible
- **WHEN** the Ottawa pack is loaded and the camera faces the river from Parliament Hill
- **THEN** a water surface is visible where the river is

### Requirement: Shoreline
Terrain inside a water polygon SHALL be lowered by the configured depth at pack build, except under flattened roads.

#### Scenario: Bank below road
- **WHEN** a residential road runs along a river bank
- **THEN** the terrain under the road stays at road height and the water cells beside it are lower

