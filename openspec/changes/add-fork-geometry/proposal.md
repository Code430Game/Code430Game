# Change: Forks and merges peel ramps off the road edge

**Status: proposed 2026-09-30 from Deck drive reports (odd lane additions at exits, ramp walls across the highway, the off-ramp by the old spawn).**

## Why
OSM draws a ramp from the through road's centreline. Rendered at full width from that point, the
ramp's ribbon sits inside the highway and pokes out of its far side, the junction polygon at the
fork covers half the carriageway, lane-count changes step instead of tapering, and every barrier
placed on the ramp's edges lands across the highway lanes. Traffic also treats the fork as a
junction and yields there.

## What Changes
- **Importer:** a node with three roads where two run straight through and the third leaves or
  arrives at a shallow angle, narrower than the road it meets, is a fork (link departs) or a
  merge (link arrives). The link's end vertex moves sideways so its inner edge sits on the
  through road's outer edge, fading out over 40 m, and the node is tagged `fork` or `merge`.
- **Game:** no junction polygon at forks and merges; the wider through edge tapers to the
  narrower one across the node; lane connectors across a fork carry no junction claim.
- **Barriers:** samples end on the edge end so walls meet across edge splits, and the overlap
  rule is height-aware so a deck crossing above another road keeps its parapet.
- **Not in this change:** lane-level gore markings, multi-lane ramps sharing more than one lane
  with the through road, ramps that fork from the inside (left exits).

## Impact
- Affected specs: `road-network` (new requirement).
- Affected code: `tools/osm_import/forks.py` (new), `pipeline.py`, `barriers.py`, schema
  `junction_type` enum; `game/world/roads/junction_builder.gd`, `road_mesh_builder.gd`,
  `road_graph.gd`, `game/world/traffic/lane_graph.gd`; golden files.
- Performance: none measurable (fewer junction polygons).
