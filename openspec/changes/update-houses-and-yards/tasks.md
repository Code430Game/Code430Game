## 1. Importer
- [x] 1.1 House type hints per footprint (kind, size, shape, levels, seed); door side and setback from the nearest street; schema; tests on fixtures. `tools/osm_import/houses.py`: party walls are edges along a neighbour (within 0.6 m over 60% of the edge), so rows and pairs come from geometry as well as the kind (a unit beside a two-party-wall unit is a terrace end, not a semi); the front wall faces the nearest street that is not a service lane; defaulted heights take the type's eave height. On the current Ottawa pack: 5,078 hints (terrace 2,093, detached 1,384, semi 873, bungalow 381, cottage 347), 65 with no street in reach, median setback 8.3 m
- [x] 1.2 `yards.py`: front lawn, backyard and side-yard polygons per house; fence lines along shared backyard boundaries, never across a driveway, path or road; `yards.v0.json`, schema, validator; tests. A lot is the land nearer its house than any other (Voronoi of outline samples), within 30 m, minus roads with a 2 m sidewalk allowance, driveways, footpaths, other buildings, parking lots and water; split by the front wall's line (front lawn) and the rear wall's line (backyard), the rest is side yard. Also exported: the path from the door across the lawn and the lawn's frontage along the street (for hedges). Fences are the shared edges of two backyards, straightened to 1 m. Overlays run on a 1 cm grid (the proving ground's regular grid gave degenerate Voronoi cells). Trial on the current Ottawa data: 5,074 yards, 4,781 paths, 6,111 fences (51 km), 14 s, about 13 MB indented. Proving ground: 1,869 yards, 2,819 fences
- [ ] 1.3 Re-export the Ottawa pack; golden fixture

## 2. Game
- [ ] 2.1 House types in `building_builder.gd`: detached front gable, cottage with dormer, bungalow, semi and terrace rows with shared roof lines; realistic heights; tests on each type's shape
- [ ] 2.2 `house_parts.gd`: door facing the street, porch or stoop with steps, window frames, sills and lintels, chimneys; LOD0 only; tests
- [ ] 2.3 Materials palette (brick, clapboard, stone trim) with tagged material and colour first; tests
- [ ] 2.4 Yards: lawn, path to the door, hedges and shrubs; fences as one MultiMesh per chunk; tests
- [ ] 2.5 Before and after screenshots on a Glebe street, a Sandy Hill terrace row and a corner lot

## 3. Verification
- [ ] 3.1 Deck benchmark on a dense residential street against main
- [ ] 3.2 Human walks a residential street on the Deck
