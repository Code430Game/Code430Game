## 1. Importer
- [ ] 1.1 `border.v0.json`: each road crossing of the district border (position, heading, lanes, way id), roadblocks tagged with their border side; schema and validator; tests on the proving ground split into two test districts

## 2. Game
- [ ] 2.1 `PackLoader`: a set of active maps, `map.neighbours`, refused sets (different origin or projection, overlapping borders) with a reason; tests
- [ ] 2.2 Chunk owner lookup in the streamer, GLB cache keyed by pack and chunk (`GENERATOR_VERSION` bump); tests
- [ ] 2.3 Road graph and lane paths joined at matching crossings (1 m, 15°), roadblocks dropped there; traffic and routing across the border; tests with the two test districts
- [ ] 2.4 Terrain border rows blended; minimap, overview map, spawns, parking and pedestrians over the union; co-op summary lists the set; tests
- [ ] 2.5 Mac screenshots: a street crossing the border, from the ground and on the overview map

## 3. Verification
- [ ] 3.1 Deck benchmark with Centretown alone and with a second district: frame avg and p99, memory, load time
- [ ] 3.2 **Stop: human drives from one district into the next on the Deck**
