## 0. Preconditions
- [ ] 0.1 Human approves the proposal (and the two open questions in design.md)

## 1. Water import (Python)
- [ ] 1.1 Overpass water query with `out geom`, cached, recorded in sources
- [ ] 1.2 Multipolygon ring assembly with tests on a synthetic relation and a committed fixture (Rideau Canal near the fixture area)
- [ ] 1.3 Clip to bbox with shapely, triangulate with mapbox_earcut, surface height from terrain
- [ ] 1.4 `water.v0.json` writer, JSON Schema in `docs/pack-format/`, determinism test
- [ ] 1.5 Shoreline lowering in `pack.py` (config depth), test
- [ ] 1.6 Report section: water polygons written, relations skipped

## 2. Water rendering (Godot)
- [ ] 2.1 `game/world/water/` loader and chunked flat meshes, material per preset
- [ ] 2.2 gdUnit4 tests: polygon count matches the file, meshes face up, chunk assignment
- [ ] 2.3 Include water in the GLB chunk export and import

## 3. Wayfinding (Godot)
- [ ] 3.1 HUD scene with current road and next cross street
- [ ] 3.2 Overview map: graph and water rendered once to a texture; map screen with player marker, heading, trigger zoom, Back to toggle
- [ ] 3.3 Minimap: corner crop of the map texture rotated to heading, road name beneath, hidden while the map is open
- [ ] 3.4 Tests: nearest-road name lookup, next cross street on a synthetic grid, map texture generated once, minimap rotation

## 4. Verification
- [ ] 4.1 Regenerate the Ottawa pack, drive to the river and open the map on the Deck; record frame time
- [ ] 4.2 **Stop: human confirms the river and the map on the Deck**
