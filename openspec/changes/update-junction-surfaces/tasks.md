## 1. Find
- [x] 1.1 `--junction-report`: degenerate polygons, untrimmed arms, terrain above the surface, with x, z; add the human's locations; a list in `design.md`
  - `JunctionReport` measures bulge (outline past what its arms need), gaps (trimmed ribbon left uncovered), hulls, point-like outlines, nodes with no surface, and terrain above, with tunnel junctions counted apart.
  - It runs from `--junction-report`, the headless `world/build/junction_report.gd`, and `test_junction_report.gd`.
  - Ottawa before: 464 bulging, 593 with gaps, 73 hulls, 0 point-like. The before and after table and the worst junctions are in `design.md`.
- [x] 1.2 Three-way blob junctions (#78 Colonel By Drive, x 998, z 1041, `n901218147`; #79 a parking aisle off Graham Avenue, x 1098, z 935, `n6020506072`)
  - **Cause:** the corner between arms whose edges never meet was pushed along `normalize(da + db)`, an arbitrary direction for a road running straight on. That gave a bulge into the grass or a notch back across the road.
  - **Fix:** the outline follows the road edge (ALONG / SHARP corners). Narrow Y splits are joined outer cap to outer cap (PAIR), and divided carriageways that touch share a widened slot.
  - **Importer:** a road dividing into carriageways has them start on its own lanes (`shape_splits`, 22 in Ottawa).
  - **Tests:** `test_junction_shapes.gd` (five fixtures), `test_osm_splits.py`, and `test_junction_report.gd`, which checks that #78 and #79 are clean and the counts stay down.

## 2. Fix
- [x] 2.1 Point-like junctions get trimmed arms and a polygon; lanes connect across; tests on each found case reduced to a fixture
  - The report found no point-like junction or node without a surface (0 and 0). The blobs above were the cases found, and each is reduced to a fixture in `test_junction_shapes.gd`.
  - Lane and marking tests pass unchanged.
- [x] 2.2 Curbs cut back to the junction polygon at curved arms; test
  - `BarrierBuilder.clip_curbs` cuts curbs to the junction outlines when the pack loads, keeping their heights.
  - Tests: a fixture, and the Ottawa pack, where no curb stands more than 0.2 m inside a junction. That test fails without the clip.
- [x] 2.3 Terrain flattened under junction polygons in the importer; `test_junction_terrain.gd` down to the junctions that are really in tunnels; pack re-exported
  - `pack._junction_corners` flattens each corner toward where its edges meet, at the arms' heights; tests in `test_osm_junction_corners.py`.
  - Terrain above a junction: 14 outside tunnels, none over 0.25 m; 9 tunnel junctions are counted apart. The test guard is now 1% and 0.5 m (was 3%).
  - The pack and golden fixture were re-exported. Before the change, the pack re-exported byte-identical from the cache.
- [x] 2.4 Before and after screenshots at each found junction
  - #78 low view: the blob is gone, and the two-way road runs into the divided pair at full width.
  - #79 from above: the notch was under a metre and is hard to see at that height; the report confirms it is gone.
  - 417 ramp merge `n905118988`: the grass blobs in the carriageway are gone.
  - Clustered crossing `c4686481171`: the median bite is covered.
  - The parking driveway wedge in #79 and the billboard standing in #78's view are not junction surfaces (`update-parking`, and the billboard backlog entry).

## 3. Verification
- [ ] 3.1 Deck benchmark against main
- [x] 3.2 Human drives the junctions they found on the Deck
  - 2026-10-21 Deck: the human: "Most junctions are better".
