# Change: District edge

**Status: proposed 2026-10-02 (human asked for a slate of proposals that other agents can pick up in fresh contexts; the backlog has wanted a subtler end-of-district marker since 2026-09-30).**

## Why
Every road the import bounding box cuts ends in a bright orange slab across its width
(importer barrier kind `roadblock`, 108 of them in Ottawa). It stops the car falling off the
map, but it reads as a bug, traffic drives up to it and U-turns on the spot, and nothing tells
the player they have reached the edge of the district rather than a broken road.

## What Changes
- **Importer:** `roadblock` barriers gain an `edge` attribute, `"closure"` by default, or
  `"wall"` to keep the old slab; `osm_import/config.json` `barriers.edge_style` sets it per
  pack. The schema and the pack validator accept the new optional field.
- **Closure dressing:** `EdgeClosureBuilder` replaces the slab for `closure` roadblocks with a
  construction-style closure: a row of striped A-frame barricades across the road, a cone
  taper over the last 15 m, a "ROAD CLOSED" sign plate, and a low solid barrier behind the
  barricades that still stops the car. Built per chunk under the existing `barriers_lod0`
  role.
- **Terrain beyond:** the terrain material fades to the fog colour over the last 60 m to the
  district bounds, in both presets, so the ground does not end in a hard line.
- **Wayfinding:** the minimap and overview map draw the district boundary as a dashed line;
  the HUD shows a short "District edge" notice when the player is within 80 m of the bounds
  and heading out, once per approach.
- **Traffic:** lane paths that end at an edge roadblock carry a turnaround distance; cars and
  buses on them slow and U-turn 40 m before the closure, and traffic never spawns within 60 m
  of it, so the edge is quiet instead of a queue.
- **Not in this change:** streaming a neighbouring district across the edge, a story reason
  for the closure, tone variants of the signage.

## Impact
- Affected specs: `street-dressing` (new requirement; roadblocks have no requirement today),
  `traffic` (new requirement), `wayfinding` (minimap modified).
- Affected code: `tools/osm_import/barriers.py`, `config.py`, `config.json`,
  `docs/pack-format/barriers.schema.v0.json`, `tools/tests/test_osm_barriers.py`;
  `game/world/barriers/barrier_builder.gd`, `edge_closure_builder.gd` (new),
  `game/world/terrain/terrain_builder.gd` (bounds uniform), `game/world/traffic/lane_graph.gd`,
  `traffic_manager.gd`, `game/ui/map/minimap.gd`, `overview_map.gd`, `map_renderer.gd`, the HUD
  in `play_testbed.gd`, `game/tests/test_barrier_builder.gd`, `test_traffic.gd`; the Ottawa
  pack re-exported.
- Co-op: closures and the terrain fade are built from pack data on every peer; the HUD notice
  is per player; traffic turnarounds run on the host like all traffic.
- Tone: the signage is plain and reads no mode flags.
- Performance: 108 closures of about 60 triangles each plus one `Label3D` per sign in NEAR
  chunks; terrain fade is one uniform. Deck measured.
