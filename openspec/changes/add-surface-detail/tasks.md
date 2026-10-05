## 1. Textures
- [x] 1.1 Detail texture generator (asphalt, concrete, joint, paint) with presets; determinism test; materials sample world-space UVs on both presets; `docs/graphics-presets.md` updated; done 2026-10-04: asphalt, concrete and paint detail (FastNoiseLite, fixed seeds, seamless) through `ground_detail.gdshader` on the road, junction, lot, sidewalk and marking materials. Deck preset 512 px, one sample; high 1024 px plus a large-scale sample against tiling. No normal maps (the ground meshes have no tangents). Built once and cached as PNGs in user:// (first build about 0.2 s at 512 px on a Mac)

- [ ] 1.2 Grass through roads: a test on the Ottawa pack counts junction surfaces with terrain above them by more than 5 cm (before); the importer flattens a disc under each junction node; Ottawa re-exported; the count after recorded here

## 2. Sidewalks
- [ ] 2.1 `sidewalk_builder.gd`: distance-along and across in UV2; joint lines in the shader; longitudinal joint on wide ribbons; test on spacing; GLB export attribute and Ottawa pack re-exported

## 3. Crossings
- [ ] 3.1 Zebra stripe quads per crossing in the marking chunks, clipped to the curb, with a stop line on signalised approaches; tests on stripe count and extent
- [ ] 3.2 Mac screenshots: Bank and Somerset crossing, a Market sidewalk with joints, asphalt grain by day and at dusk on both presets

## 4. Verification
- [ ] 4.1 Deck benchmark on the usual route, both presets; no regression on `deck`
- [ ] 4.2 **Stop: human walks a crossing and a block of sidewalk downtown on the Deck**
