## 0. Preconditions
- [x] 0.1 Human approves the proposal (2026-09-30; marker list yes, dark style)

## 1. Water import (Python)
- [x] 1.1 Overpass water query with `out geom`, cached, recorded in sources
- [x] 1.2 Multipolygon ring assembly with tests on a synthetic relation and a committed fixture (Rideau Canal near the fixture area)
- [x] 1.3 Clip to bbox with shapely, triangulate with mapbox_earcut, surface height from terrain
- [x] 1.4 `water.v0.json` writer, JSON Schema in `docs/pack-format/`, determinism test
- [x] 1.5 Shoreline lowering in `pack.py` (config depth), test
- [x] 1.6 Report section: water polygons written, relations skipped

## 2. Water rendering (Godot)
- [x] 2.1 `game/world/water/` loader and chunked flat meshes, material per preset
- [x] 2.2 gdUnit4 tests: polygon count matches the file, meshes face up, chunk assignment
- [x] 2.3 Include water in the GLB chunk export and import

## 3. Wayfinding (Godot)
- [x] 3.1 Remove the road-name text from the drive HUD (keep it in telemetry)
- [x] 3.2 Overview map: graph and water rendered once to a texture; map screen with player marker, heading, current road name beside the marker, trigger zoom, right-stick cursor that highlights the hovered road and shows its name, Back to toggle
- [x] 3.3 Minimap: corner crop of the map texture rotated to heading, no text, hidden while the map is open
- [x] 3.4 Tests: nearest-road name lookup, map texture generated once, minimap rotation

## 4. Verification
- [x] 4.1 Regenerate the Ottawa pack, drive to the river and open the map on the Deck; record frame time (Steam Deck, deck preset, 30 s autodrive on Colonel By Drive beside the canal: avg 5.6 ms, p99 6.1 ms, max 12.9 ms; map texture 1792x1792 renders in 0.8 s at load)
- [x] 4.2 **Stop: human confirms the river and the map on the Deck** (2026-09-30: "the maps look amazing")
