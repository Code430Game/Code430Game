# Change: Add water surfaces and wayfinding (road names, overview map)

**Status: PROPOSED 2026-09-30, awaiting the human's approval.** Raised after the first Deck drive: without landmarks, road names, or a map it is hard to tell where you are; the first thing the human's partner looked for was the river.

## Why
Ottawa is defined by its rivers and canal. Rendering water gives the city its first real landmark and makes the street grid legible. A minimap and an overview map (the seed of the in-game GPS) turn "I think I went up Metcalfe" into knowing.

## What Changes
- **Map packs gain water polygons.** The import tool fetches OpenStreetMap water (`natural=water`, `waterway=riverbank`, multipolygon relations), assembles rings, clips them to the district bbox, triangulates them, and writes `water.v0.json` with a surface height per polygon taken from the terrain. The Ottawa pack gets the Ottawa River, the Rideau River, the Rideau Canal, and Dow's Lake.
- **The game draws water** as flat surfaces at the recorded height with a simple water material, in both presets, chunked like roads. Terrain under water is lowered slightly so shorelines read.
- **Overview map**: a toggleable full-screen top-down map rendered from the road graph and water polygons (not a camera), centred on the player with heading, zoomable with the triggers. The GTA pause-menu map. This is the first form of the GPS; routing comes later.
- **Minimap**: the same map texture shown in a corner while driving, rotated to the car's heading. The GTA and Cyberpunk radar layout, without blips or routes yet. No street name text while driving; the human found that distracting. The overview map prints the current road next to the player marker instead.
- **Not in this change:** buildings, bridges over water as 3D structures, turn-by-turn routing, mission blips, any always-on text HUD.

## Impact
- Affected specs: `map-water` (new), `wayfinding` (new). Pack format v0 gains an optional `water.v0.json` (documented in `docs/pack-format/`); no shipped format changes since v0 has not shipped.
- Affected code: `tools/osm_import/` (water fetch, ring assembly, clipping, triangulation), `game/world/water/` (new), `game/ui/` (HUD, overview map).
- New tool dependencies: `shapely` for clipping and `mapbox_earcut` for triangulation with holes. Both free and pip-installable.
- Performance: water is a handful of large flat polygons; negligible. The overview map renders lines to a texture once and pans it, so it costs nothing while hidden.
