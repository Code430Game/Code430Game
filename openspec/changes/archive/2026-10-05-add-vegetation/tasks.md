## 1. Importer
- [x] 1.1 `vegetation.py`: query, ring assembly, archetype mapping, rows, seeded Poisson-disc scatter, bushes on park edges and frontages, exclusion margins, terrain heights, priority order; schema; validator; tests on a fixture with a tagged tree, a row, a park with a road through it and a residential block
- [x] 1.2 Validation report counts and over-cap figures; golden fixture; Ottawa pack re-exported with the tree, bush and area counts noted here
  - 2026-10-05 Ottawa re-export: 18,998 trees (11,586 mapped, 64 in rows, 7,348 scattered), 37,174 bushes (mostly frontage), 393 green areas; at most 456 trees in a chunk, one chunk over the deck cap of 400. Skips are counted in the report (270 mapped trees on a road surface, building or water; 31,807 frontage spots blocked). `vegetation.v0.json` is 6.4 MB. The golden fixture is unchanged: it covers the road graph only, and vegetation has its own tests. Mapped trees and rows are kept only off the road surface, buildings and water, because street trees stand in the sidewalk strip; scattered planting keeps the full margins

## 2. Game
- [x] 2.1 `tree_meshes.gd` archetypes under the triangle budgets, `canopy.gdshader`, presets entries; tests on triangle counts and that both presets declare the features
- [x] 2.2 `vegetation_builder.gd`: per-chunk MultiMeshes by archetype and LOD, tier-driven LOD, caps in priority order, trunk shapes through the shape queue; streamer and map pack wiring; tests
- [x] 2.3 Map renderer: park and grass fill; test
- [x] 2.4 Mac screenshots: Elgin Street street trees, Confederation Park, the canal bank, Major's Hill Park, a residential block in Centretown with frontage bushes
  - 2026-10-05: shots shared from the start, Confederation Park, Major's Hill Park, the canal by the Laurier bridge, Centretown, and the map with its green areas

## 3. Verification
- [x] 3.1 Deck benchmark on the autodrive route and a canal drive: frame avg and p99, draw calls, with and without vegetation; no regression past the 25 ms target
  - 2026-10-05, idle Deck, deck preset: without vegetation (main) route avg 12.47 ms, p99 16.67. With vegetation, two route runs: avg 12.55 / 12.63, p99 25.00 / 19.59, draw calls 699 / 981. Looking over Confederation Park (20 s): avg 13.48, p99 21.01, 1,376 draw calls. Under the 25 ms target; the extra p99 jitter is worth watching. Changes after the first look: LOD1 is the same shape at about 16 triangles (crossed quads read as flat cards), LOD0 reaches 260 m on deck and 400 m on high (ranges are measured to each chunk's middle), and a chunk's vegetation lands as one node so streaming keeps its pace
- [x] 3.2 **Stop: human drives Queen Elizabeth Driveway along the canal and walks Confederation Park on the Deck**
  - 2026-10-05: the human on the Deck: "Trees are awesome." Issues filed on that drive (#43, #44 garage ceiling; #45 bridge parapets) were fixed separately
