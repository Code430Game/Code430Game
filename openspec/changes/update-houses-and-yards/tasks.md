## 1. Importer
- [ ] 1.1 House type hints per footprint (kind, size, shape, levels, seed); door side and setback from the nearest street; schema; tests on fixtures
- [ ] 1.2 `yards.py`: front lawn, backyard and side-yard polygons per house; fence lines along shared backyard boundaries, never across a driveway, path or road; `yards.v0.json`, schema, validator; tests
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
