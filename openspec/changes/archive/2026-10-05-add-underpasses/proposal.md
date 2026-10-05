# Change: Underpasses

**Status: proposed 2026-10-01 (human: the pedestrian tunnel by the Chateau, the path under the Portage approaches, "fell through the map").**

## Why
Covered pedestrian ways (tunnel=yes, covered=yes) import but are not drawn, so a path that
dives under a road simply stops, and whatever joins it ends in mid-air or at a terrain step.
An underpass should be a place: a cutting that leads down, a concrete passage under the road,
and the way out on the other side.

## What Changes
- **Importer stage `underpasses`** (after pedestrian heights, before terrain flattening): for
  each covered footway, path, cycleway or pedestrian way that joins open ways and is under
  80 m, sample what covers it (the carved terrain and any ground road over it). With real
  cover the way becomes a `tunnel`: a flat floor at least 3.4 m below the highest cover
  point and never above the joined ends, a ceiling 0.3 m under the cover; the joined ways
  ramp down to the floor at 15 % (stairs at 60 %) and are marked `trench`. Without cover
  (the carved ground under a bridge, a tunnel the DEM already shows as a dip) the way is
  uncovered and drawn like any path, and its joined ways ramp to meet it.
- **Terrain** follows tunnel floors and trench ramps within half width + 1 m instead of the
  road margin, so the cutting is narrow.
- **Game:** `UnderpassBuilder` draws tunnel floors, side walls, a ceiling slab that also
  hides the cutting from above, and headwalls at both portals, with collision; a new
  `underpasses_lod0` NEAR role. Pedestrians still do not path through tunnels.
- **Pack format:** pedestrian ways gain optional `profile` (`tunnel` | `trench`) and `top`
  (ceiling height per point, tunnels only).
- **Not in this change:** lighting inside, retaining walls along trenches, a sheltering
  population (tone-gated, waits for add-content-modes).

## Impact
- Affected specs: `street-dressing` (new requirement).
- Affected code: `tools/osm_import/underpasses.py` (new), `pack.py` (margin per segment,
  stage call), `graph.py`, `export.py`, schema; `game/world/roads/underpass_builder.gd`
  (new), `road_graph.gd`, `map_pack.gd`; tests; the Ottawa pack re-exported.
