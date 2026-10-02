## 1. Importer
- [x] 1.1 `underpasses.py`: cover sampling, floor and ceiling, approach ramps, uncover without cover; per-segment terrain margin; tests
- [x] 1.2 Export `profile` and `top`; schema; Ottawa pack re-exported (19 tunnels dug, 19 covered ways opened, 62 approach trenches)

## 2. Game
- [x] 2.1 `UnderpassBuilder`: floor, thick walls, roof slab, headwalls, collision, terrain strip cut under the passage (`TerrainBuilder` holes); `underpasses_lod0` role; tests
- [x] 2.2 Mac screenshots (2026-10-01): Nicholas Street portal, Chateau tunnel portal, inside and overhead; the cuttings read as sunken paths, interiors are dim but readable

## 3. Verification
- [x] 3.1 Deck (2026-10-01): avg 13.6 ms, p99 22.3, GPU 8.3, unchanged
- [x] 3.2 Human walked through the Portage cycleway underpass on the Deck (2026-10-02); cars were seen on the path there: an untagged layer=-2 garage ramp coincided with it, now treated as a tunnel and kept free of traffic
