# Change: Neighbouring districts played as one map

**Status: proposed 2026-10-20 (human: "One pack per district, can we load multiple?" and, on
keeping stitching possible, "Sureeeeee… ya. That makes sense in a way. I hope it works.").**

## Why
`add-pack-repositories` makes a location repository a city with one pack per district, so
several people can map different parts of Ottawa. Today the game plays one map pack
(`PackLoader.active_map`), and every road the district's bounding box cuts ends at a
roadblock, so Centretown and a future Glebe would be two separate maps rather than one city.
Because districts in a city share the city's pinned origin and have borders on the 256 m chunk
grid (rules added in `add-pack-repositories`), their coordinates already line up and each
chunk belongs to exactly one district. This change lets the game play a set of neighbouring
districts together.

## What Changes
- **A map is one or more districts.** The map in play is joined by every installed map pack of
  the same city (same origin and projection, a border that overlaps none already taken): found,
  not listed, so installing a neighbouring district is enough. (Planned as `map.neighbours`;
  changed 2026-10-22 while building it.) The scene can name a set of map packs to play together;
  they must share an origin and projection, and their borders must not overlap. The loader
  refuses a set that breaks either rule, with the reason on the Packs tab.
- **Chunks come from the district that owns them.** The streamer looks up each chunk's owner
  from the districts' borders and builds it from that pack's data. The GLB chunk cache is keyed
  by pack and chunk, as it is by chunk today, so a district's cache is unchanged by its
  neighbours.
- **Roads join at shared borders.** Where two loaded districts meet, the importer's edge
  roadblocks on that border are dropped and the road graphs are joined: the importer writes
  each border crossing (position, heading, lanes) into a `border.v0.json`, and the game links
  crossings of neighbouring districts that match within 1 m and 15°. Unmatched crossings keep
  their roadblock (`add-district-edge`'s closure where that has landed). Traffic, buses and
  routing use the joined graph.
- **Terrain meets without a seam.** Each district's terrain already samples the same DEM; the
  border rows of neighbouring heightmaps are averaged at load so the ground has no step.
- **Wayfinding treats the set as one map.** The minimap and overview map draw every loaded
  district, with the outer edge of the set as the district edge. Spawns, parking and
  pedestrians use the union.
- **Co-op compares the whole set.** The co-op summary lists every map pack in play with its
  version and content hash, and a client missing one is refused as today.
- **Memory and the Deck.** Only chunks near the players are built, so playing two districts
  costs the larger road graph, building index and lane paths, not twice the chunks. The change
  measures that on the Deck before it is accepted.
- **Not in this change:** districts from different cities, overlapping districts, streaming in
  a district's data only when the player approaches it (all districts in the set load at
  start), and editing borders in game.

## Impact
- Affected specs: `world-streaming` (ADDED: Districts Played Together; ADDED: Roads Across
  District Borders).
- Affected code: `PackLoader` (a set of active maps), `MapPack` and the chunk streamer (chunk
  owner lookup), `glb_chunks.gd` (cache key per pack), the road graph and lane paths (joined
  at crossings), terrain border blending, minimap and overview map, spawn and population
  code, the co-op summary; the importer (`border.v0.json`, roadblocks tagged with their
  border side) and its schema.
- Depends on `add-pack-repositories` (shared origin, borders on the chunk grid). Works with
  `add-district-edge` (closures stay on unmatched crossings).
