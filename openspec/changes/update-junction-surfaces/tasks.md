## 1. Find
- [ ] 1.1 `--junction-report`: degenerate polygons, untrimmed arms, terrain above the surface, with x, z; add the human's locations; a list in `design.md`

## 2. Fix
- [ ] 2.1 Point-like junctions get trimmed arms and a polygon; lanes connect across; tests on each found case reduced to a fixture
- [ ] 2.2 Curbs cut back to the junction polygon at curved arms; test
- [ ] 2.3 Terrain flattened under junction polygons in the importer; `test_junction_terrain.gd` down to the junctions that are really in tunnels; pack re-exported
- [ ] 2.4 Before and after screenshots at each found junction

## 3. Verification
- [ ] 3.1 Deck benchmark against main
- [ ] 3.2 Human drives the junctions they found on the Deck
