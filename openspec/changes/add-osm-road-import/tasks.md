## 1. Pipeline skeleton
- [ ] 1.1 Create `tools/osm_import/` package with CLI (`python -m osm_import --bbox ... --out ...`)
- [ ] 1.2 Config file for class defaults (lanes, widths, speeds, clearance, max grades, cluster radii)
- [ ] 1.3 Fetch + cache (Overpass bbox; optional local .osm.pbf); record source and timestamp
- [ ] 1.4 Small fixture area (a few blocks + one ramp) committed as a test extract, under ODbL attribution

## 2. Graph build
- [ ] 2.1 Filter drivable and pedestrian ways
- [ ] 2.2 Project to UTM 18N and local origin
- [ ] 2.3 Build nodes/edges with polylines and OSM ids
- [ ] 2.4 Fill defaults and record defaulted fields
- [ ] 2.5 Junction clustering (never across layers)
- [ ] 2.6 Golden-file tests on fixture

## 3. Validation report
- [ ] 3.1 Connected components
- [ ] 3.2 Dead-end classification (real vs. bbox-edge vs. suspicious)
- [ ] 3.3 Ramp (`*_link`) connectivity checks
- [ ] 3.4 One-way trap detection (strongly connected components)
- [ ] 3.5 Markdown + JSON report output
- [ ] 3.6 **Stop: run on the full starter district and show the human the report**

## 4. Elevation
- [ ] 4.1 DEM download + cache + sampling
- [ ] 4.2 Bridge/tunnel elevation from layer tags with grade-limited ramps
- [ ] 4.3 Road profile smoothing per class max grade
- [ ] 4.4 Tests on fixture ramp

## 5. Export
- [ ] 5.1 `road_graph.v0.json` writer
- [ ] 5.2 JSON Schema in `docs/pack-format/road_graph.schema.v0.json`, validated in CI
- [ ] 5.3 Determinism test (two runs → identical bytes)

## 6. Mesh generation (Godot)
- [ ] 6.1 Graph reader in `game/world/roads/`
- [ ] 6.2 Road segment extrusion
- [ ] 6.3 Junction polygon construction + trimming + fallback
- [ ] 6.4 Terrain heightmap with road flattening
- [ ] 6.5 Chunking (256 m), LODs, collision
- [ ] 6.6 Export chunks as GLB into the map pack
- [ ] 6.7 gdUnit4 tests (chunk counts, no gaps at chunk seams, collision present)

## 7. Map pack + testbed
- [ ] 7.1 `packs/ottawa-centretown/` with `pack.json` (type: map, ODbL + DEM attribution), road graph, chunks, `overrides.json` (empty)
- [ ] 7.2 Testbed scene loading the pack's chunks (static load is fine; streaming is later)
- [ ] 7.3 Placeholder car (Jolt VehicleBody3D), chase camera, controller driving
- [ ] 7.4 Debug view: toggle to draw the road graph (edges colored by class, junctions, one-way arrows)
- [ ] 7.5 Profile on `deck` preset; record frame time in the PR
- [ ] 7.6 **Stop: human drives it on the Steam Deck (Queensway → exit → ByWard Market)**
