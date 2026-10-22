## 1. Importer
- [x] 1.1 `border.v0.json`: each road crossing of the district border (position, heading, lanes, way id), roadblocks tagged with their border side; schema and validator; tests on the proving ground split into two test districts
  - 2026-10-22: `tools/osm_import/border.py`. With a border, `run_pipeline` cuts the graph after the heights are final (both neighbours grade the road with what lies beyond the line, so the heights at the cut agree), then barriers and the rest see the cut graph. A road leaving ends at a `b<n>` dead-end node on the line; a road that leaves and comes back makes pieces `<id>b<k>`; footways are cut the same way; bus stops outside go. Each line has one owner (a district owns its west and north lines), so a road lying along a line isn't in both. Only the cut ends get roadblocks (a real dead end near the border keeps none), tagged `border_side`. Schemas: `border.schema.v0.json`; road graph ids allow `b` nodes (with no OSM ids) and `b<k>` pieces; barriers allow `border_side`; the validator checks `border.v0.json`. Tests (`test_osm_border.py`): the proving ground split at x = 256 m into two districts gives 10 crossings each way, every one paired (same place within 1 m, opposite heading, lanes swapped, heights within 5 cm); the cut graph stays inside and validates; roadblocks are tagged. Not yet re-exported: Centretown 0.3.0 has no `border.v0.json`; its next export (with a second district) will.

## 2. Game
- [ ] 2.1 `PackLoader`: a set of active maps, `map.neighbours`, refused sets (different origin or projection, overlapping borders) with a reason; tests
- [ ] 2.2 Chunk owner lookup in the streamer, GLB cache keyed by pack and chunk (`GENERATOR_VERSION` bump); tests
- [ ] 2.3 Road graph and lane paths joined at matching crossings (1 m, 15°), roadblocks dropped there; traffic and routing across the border; tests with the two test districts
- [ ] 2.4 Terrain border rows blended; minimap, overview map, spawns, parking and pedestrians over the union; co-op summary lists the set; tests
- [ ] 2.5 Mac screenshots: a street crossing the border, from the ground and on the overview map

## 3. Verification
- [ ] 3.1 Deck benchmark with Centretown alone and with a second district: frame avg and p99, memory, load time
- [ ] 3.2 **Stop: human drives from one district into the next on the Deck**
