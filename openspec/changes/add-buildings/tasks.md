## 1. Import
- [x] 1.1 Overpass building query with member geometry, cached; ring assembly reused from water
- [x] 1.2 Height rules in config (storey height per type, defaults); `buildings.v0.json` writer and schema; fixture and tests
- [x] 1.3 Terrain flattened under footprints at pack build; report section

## 2. Game
- [x] 2.1 `building_builder.gd`: extrude walls and roofs per chunk, per-type colours, upward winding, collision
- [x] 2.2 LOD and visibility ranges; GLB export and import
- [x] 2.3 Map renderer draws footprints

## 3. Verification
- [x] 3.1 gdUnit4: count matches file, winding, chunk assignment, GLB round trip
- [ ] 3.2 Deck frame time downtown; screenshots on Wellington and in the Market
- [ ] 3.3 **Stop: human drives downtown on the Deck**
