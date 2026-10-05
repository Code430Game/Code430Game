# vegetation Specification

## Purpose
Trees, bushes and green areas from OpenStreetMap (mapped street trees, tree rows, parks, gardens, grass and woods), drawn per chunk in two levels of detail under per-preset caps that keep mapped trees first, with green areas on the maps.

## Requirements

### Requirement: Vegetation In Map Packs
The import tool SHALL write `vegetation.v0.json` with trees and bushes placed from OpenStreetMap tree nodes, tree rows and wooded, park, grass and scrub areas, scattered deterministically by seed, kept off roads, sidewalks, buildings and water by a margin, with ground heights from the terrain and each chunk's list in priority order (tagged, rows, scatter).

#### Scenario: Tagged street tree
- **WHEN** a `natural=tree` node with `genus=Acer` and `height=9` is inside the bbox
- **THEN** one tree is exported at that position with the broadleaf archetype and height 9

#### Scenario: Park with a road through it
- **WHEN** a `leisure=park` polygon is crossed by a road
- **THEN** scattered trees fill the park at the park spacing and none stands within the road's margin

#### Scenario: Deterministic
- **WHEN** the importer runs twice on the same extract and seed
- **THEN** the vegetation files are byte-identical

### Requirement: Instanced Trees And Bushes
The game SHALL draw trees and bushes as per-chunk instanced meshes with two LODs selected by the chunk's streaming tier, capped per chunk by the active preset in the pack's priority order, with trunk collision near roads in the near tier, and no city-wide instanced mesh.

#### Scenario: Deck cap
- **WHEN** a chunk holds more trees than the `deck` cap
- **THEN** the chunk shows the first cap trees in priority order and every tagged street tree is among them

#### Scenario: Tiers
- **WHEN** a chunk moves from the near tier to the mid tier
- **THEN** its full tree meshes are replaced by the impostor set, and when it goes far nothing of it remains

#### Scenario: Tree by the road
- **WHEN** the player's car hits a tree trunk beside a street
- **THEN** the car stops against it

#### Scenario: Both presets
- **WHEN** vegetation is rendered on the `deck` preset
- **THEN** canopies do not sway and per-chunk draw calls stay within the archetype times LOD count
