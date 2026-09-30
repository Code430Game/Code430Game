# Change: Add buildings from OpenStreetMap footprints

**Status: APPROVED by the human on 2026-09-30** (second in the queue after lane markings).

## Why
Streets between flat green blocks read as a diagram. Extruded building footprints turn them into a city, make Parliament and the Market recognisable, and give the map hover more to point at later.

## What Changes
- Import: fetch `building=*` ways and multipolygon relations for the bbox (same fetch, ring assembly, and clipping as water), with height from `height`, `building:levels` × a per-type storey height, or a per-type default. Write `buildings.v0.json` (footprint rings plus height and ground height) with a schema.
- Game: extrude footprints into walls and flat roofs per chunk, with a simple per-type colour, collision, and LODs (LOD1 drops small buildings, LOD2 merges nothing but hides beyond range). Included in the GLB chunks.
- Terrain under a footprint is flattened to the building's ground height at pack build so buildings do not float or sink.
- Map: footprints drawn on the overview map and minimap as a dim fill.
- **Not in this change:** textures, windows, doors, interiors, roofs other than flat, named landmark models.

## Impact
- Affected specs: `map-buildings` (new); `wayfinding` (map draws footprints, additive).
- Affected code: `tools/osm_import/buildings.py` (new), `pack.py`, `game/world/buildings/` (new), `map_pack.gd`, `glb_chunks.gd`, `ui/map/map_renderer.gd`.
- Performance: Centretown has on the order of 10 thousand footprints; boxes at ~12 triangles each are cheap, but draw calls must stay per chunk (one mesh per chunk). Deck frame time to be recorded.
