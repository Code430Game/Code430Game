# map-buildings Specification

## Purpose
TBD - created by archiving change add-buildings. Update Purpose after archive.
## Requirements
### Requirement: Building Footprints In Map Packs
The import tool SHALL write `buildings.v0.json` with every building footprint intersecting the bbox, clipped, with a height derived from OSM tags or a per-type default, and a ground height from the terrain.

#### Scenario: Tagged height
- **WHEN** a building way has `height=24`
- **THEN** its entry has height 24

#### Scenario: Levels only
- **WHEN** a building has `building:levels=3` and no height
- **THEN** its height is 3 times the configured storey height

### Requirement: Extruded Buildings
The game SHALL extrude each footprint into walls and a flat roof at its ground height, one mesh per chunk, with collision, in both presets.

#### Scenario: Parliament block
- **WHEN** the Ottawa pack is loaded near Wellington Street
- **THEN** building volumes stand on the blocks beside the road without floating or sinking

### Requirement: Footprints On Maps
The overview map and minimap SHALL draw building footprints as a dim fill under the roads.

#### Scenario: Map open downtown
- **WHEN** the map is open over Centretown
- **THEN** blocks show filled footprints between the streets

