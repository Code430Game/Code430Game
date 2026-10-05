## 1. Textures
- [x] 1.1 Detail texture generator (asphalt, concrete, joint, paint) with presets; determinism test; materials sample world-space UVs on both presets; `docs/graphics-presets.md` updated; done 2026-10-04: asphalt, concrete and paint detail (FastNoiseLite, fixed seeds, seamless) through `ground_detail.gdshader` on the road, junction, lot, sidewalk and marking materials. Deck preset 512 px, one sample; high 1024 px plus a large-scale sample against tiling. No normal maps (the ground meshes have no tangents). Built once and cached as PNGs in user:// (first build about 0.2 s at 512 px on a Mac)

- [x] 1.2 Grass through roads: `test_junction_terrain.gd` samples every Ottawa junction 60% and 85% of the way to its outline and counts terrain more than 5 cm above the surface: 16 of 915 (main's pack). Flattening a disc under each junction in the importer, then lowering terrain under junctions in a separate step, both re-exported and measured: 15 of 915, so the importer change was dropped rather than re-exporting the whole pack for one junction (the corner problem was already fixed by `update-cluster-junction-arms`). The test stays as a regression guard at 16; the remaining junctions (two around 10 m, likely cuttings or tunnel mouths) are listed in the backlog for a case-by-case look

## 2. Sidewalks
- [x] 2.1 `sidewalk_builder.gd`: distance-along and across in UV2; joint lines in the shader; longitudinal joint on wide ribbons; test on spacing; GLB export attribute and Ottawa pack re-exported; done 2026-10-04: UV = metres along and across, UV2 = (width, slab length: 1.5 m sidewalks and footways, 2 m paths, none on crossings, cycle lanes and steps); no pack re-export needed (sidewalks are built at runtime and GLB keeps both UV sets)

## 3. Crossings
- [x] 3.1 Zebra stripe quads per crossing in the marking chunks, clipped to the curb, with a stop line on signalised approaches; tests on stripe count and extent; done 2026-10-04: 1,151 Ottawa crossings striped; bars 0.5 m with 0.5 m gaps, long side along the road, 0.3 m inside the carriageway, drawn on top of the crossing's own strip (now road grey so the stripes carry it). Stop lines are new (nothing drew them before): 2 m before the stripes, across the lanes heading into a signalised junction within 35 m
- [ ] 3.2 Mac screenshots: Bank and Somerset crossing, a Market sidewalk with joints, asphalt grain by day and at dusk on both presets

## 4. Verification
- [ ] 4.1 Deck benchmark on the usual route, both presets; no regression on `deck`
- [ ] 4.2 **Stop: human walks a crossing and a block of sidewalk downtown on the Deck**
