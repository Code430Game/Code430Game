## 1. Pipeline skeleton
- [x] 1.1 Create `tools/osm_import/` package with CLI (`python -m osm_import --bbox ... --out ...`)
- [x] 1.2 Config file for class defaults (lanes, widths, speeds, clearance, max grades, cluster radii)
- [x] 1.3 Fetch + cache (Overpass bbox; local Overpass-JSON file via `--osm-json`); record source and timestamp. `.osm.pbf` input not done: needs the osmium dependency, deferred until a reproducible build is needed
- [x] 1.4 Small fixture area (a few blocks + one ramp) committed as a test extract, under ODbL attribution

## 2. Graph build
- [x] 2.1 Filter drivable and pedestrian ways
- [x] 2.2 Project to UTM 18N and local origin
- [x] 2.3 Build nodes/edges with polylines and OSM ids
- [x] 2.4 Fill defaults and record defaulted fields
- [x] 2.5 Junction clustering (never across layers)
- [x] 2.6 Golden-file tests on fixture

## 3. Validation report
- [x] 3.1 Connected components
- [x] 3.2 Dead-end classification (real vs. bbox-edge vs. suspicious)
- [x] 3.3 Ramp (`*_link`) connectivity checks
- [x] 3.4 One-way trap detection (strongly connected components)
- [x] 3.5 Markdown + JSON report output
- [ ] 3.6 **Stop: run on the full starter district and show the human the report**

## 4. Elevation
- [x] 4.1 DEM download + cache + sampling
- [x] 4.2 Bridge/tunnel elevation from layer tags with grade-limited ramps
- [x] 4.3 Road profile smoothing per class max grade
- [x] 4.4 Tests on fixture ramp

## 5. Export
- [x] 5.1 `road_graph.v0.json` writer
- [x] 5.2 JSON Schema in `docs/pack-format/road_graph.schema.v0.json`, validated in CI (pytest golden test validates the fixture output against it)
- [x] 5.3 Determinism test (two runs → identical bytes)

## 6. Mesh generation (Godot)
- [ ] 6.1 Graph reader in `game/world/roads/`
- [ ] 6.2 Road segment extrusion
- [ ] 6.3 Junction polygon construction + trimming + fallback
- [x] 6.4 Terrain heightmap with road flattening (done in Python at pack build: `osm_import/pack.py` flattens under roads with a blended shoulder and carves the DTM's bridge decks; Godot only meshes the heightmap)
- [ ] 6.5 Chunking (256 m), LODs, collision
- [ ] 6.6 Export chunks as GLB into the map pack
- [ ] 6.7 gdUnit4 tests (chunk counts, no gaps at chunk seams, collision present)

## 7. Map pack + testbed
- [x] 7.1 `packs/ottawa-centretown/` with `pack.json` (type: map, ODbL + DEM attribution), road graph, terrain heightmaps, `overrides.json` (empty). GLB chunks are a build product (see 6.6) and are gitignored
- [ ] 7.2 Testbed scene loading the pack's chunks (static load is fine; streaming is later)
- [ ] 7.3 Placeholder car (Jolt VehicleBody3D), chase camera, controller driving
- [ ] 7.4 Debug view: toggle to draw the road graph (edges colored by class, junctions, one-way arrows)
- [ ] 7.5 Profile on `deck` preset; record frame time in the PR
- [ ] 7.6 **Stop: human drives it on the Steam Deck (Queensway → exit → ByWard Market)**

## 8. Follow-ups (not part of this change)
- [ ] 8.1 Bring back `service=parking_aisle` and `service=driveway` ways (decision 2026-09-30: dropped for now; needed later to drive into lots and to reconnect the private-road islands listed in the validation report)
- [ ] 8.2 Local `.osm.pbf` input via osmium for reproducible builds
