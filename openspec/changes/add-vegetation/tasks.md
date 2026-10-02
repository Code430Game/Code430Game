## 1. Importer
- [ ] 1.1 `vegetation.py`: query, ring assembly, archetype mapping, rows, seeded Poisson-disc scatter, bushes on park edges and frontages, exclusion margins, terrain heights, priority order; schema; validator; tests on a fixture with a tagged tree, a row, a park with a road through it and a residential block
- [ ] 1.2 Validation report counts and over-cap figures; golden fixture; Ottawa pack re-exported with the tree, bush and area counts noted here

## 2. Game
- [ ] 2.1 `tree_meshes.gd` archetypes under the triangle budgets, `canopy.gdshader`, presets entries; tests on triangle counts and that both presets declare the features
- [ ] 2.2 `vegetation_builder.gd`: per-chunk MultiMeshes by archetype and LOD, tier-driven LOD, caps in priority order, trunk shapes through the shape queue; streamer and map pack wiring; tests
- [ ] 2.3 Map renderer: park and grass fill; test
- [ ] 2.4 Mac screenshots: Elgin Street street trees, Confederation Park, the canal bank, Major's Hill Park, a residential block in Centretown with frontage bushes

## 3. Verification
- [ ] 3.1 Deck benchmark on the autodrive route and a canal drive: frame avg and p99, draw calls, with and without vegetation; no regression past the 25 ms target
- [ ] 3.2 **Stop: human drives Queen Elizabeth Driveway along the canal and walks Confederation Park on the Deck**
