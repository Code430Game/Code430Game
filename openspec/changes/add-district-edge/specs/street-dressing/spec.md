## ADDED Requirements

### Requirement: District Edge Closures
Where the import bounds cut a road, the pack SHALL carry a roadblock with an edge style, and the game SHALL draw a `closure` style as a construction closure (barricades, cones, sign) with a solid stop behind it, SHALL draw a `wall` style as the plain slab, and SHALL fade the terrain to the fog colour toward the bounds in both presets.

#### Scenario: Cut road
- **WHEN** the player drives to the end of a road the bounds cut, exported with the default style
- **THEN** cones narrow the road, a row of striped barricades and a road-closed sign stand across it, and the car stops against them without falling off the map

#### Scenario: Wall style
- **WHEN** a pack exports its roadblocks with the `wall` style
- **THEN** the slab is drawn as before

#### Scenario: Ground beyond
- **WHEN** the player looks past a closure toward the bounds
- **THEN** the terrain fades into the sky colour rather than ending in a hard line
