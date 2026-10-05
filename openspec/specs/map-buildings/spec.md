# map-buildings Specification

## Purpose
Buildings from OSM footprints: carried in the map pack, extruded to their height with roofs and facades in the game, and drawn as footprints on the maps.

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

### Requirement: Facades From Data
Buildings SHALL choose their facade treatment and colour from OSM material, colour, kind and height, with a per-building seed deciding only within a treatment's palette, so the same building always looks the same and tagged colours are honoured.

#### Scenario: Tagged colour
- **WHEN** a building carries `building:colour`
- **THEN** its walls use that colour

### Requirement: Roof Shapes
Houses and small buildings SHALL get gabled or hipped roofs from `roof:shape`, or a gable along the long axis when untagged and under the house height limit; flat roofs over the parapet height SHALL carry a parapet lip and tall roofs mechanical boxes.

#### Scenario: Untagged house
- **WHEN** a house has no roof tags and is under 12 m
- **THEN** it gets a gabled roof along its longer side

### Requirement: Street Level
Buildings with a shop or amenity tag or a retail kind SHALL get a glass shopfront ground storey with an awning band on walls longer than 6 m, and apartment blocks over 12 m SHALL get balconies on their long sides.

#### Scenario: Bank Street
- **WHEN** the player walks a commercial block
- **THEN** the ground floors show shopfronts and awnings in varied colours
