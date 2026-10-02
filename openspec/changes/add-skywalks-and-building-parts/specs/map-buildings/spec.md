## MODIFIED Requirements

### Requirement: Building Footprints In Map Packs
The import tool SHALL write `buildings.v0.json` with every building footprint intersecting the bbox, clipped, with a height derived from OSM tags or a per-type default, a ground height from the terrain, a minimum height for raised parts from `min_height` or `building:min_level`, a bridge flag for `building=bridge`, and a road-span flag with a clearance height where the footprint spans a drivable road that lies well below the ground height.

#### Scenario: Tagged height
- **WHEN** a building way has `height=24`
- **THEN** the exported footprint has `height_m` 24 and `height_source` "tag"

#### Scenario: Raised part
- **WHEN** a building part has `min_height=12.2` and `height=16`
- **THEN** the exported footprint has `min_height_m` 12.2 and `height_m` 16

#### Scenario: Building over a sunken road
- **WHEN** a footprint spans a road whose surface is more than the span threshold below the footprint's median ground
- **THEN** the footprint is exported with `spans_road` true and a `clearance_y` above the road

### Requirement: Extruded Buildings
The game SHALL extrude each footprint into walls and a flat roof at its ground height, one mesh per chunk, with collision, in both presets; raised parts SHALL start at their minimum height with an underside, and a building that spans a road SHALL leave a covered opening above the road with collision only above the clearance height.

#### Scenario: Parliament block
- **WHEN** the Ottawa pack is loaded near Wellington Street
- **THEN** the blocks there are solid extruded buildings the player cannot walk through

#### Scenario: Drive under a spanning building
- **WHEN** the player drives Boulevard Maisonneuve under Place du Centre
- **THEN** the road passes through an opening with a visible underside above the car and nothing floats unsupported
