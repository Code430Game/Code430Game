# Change: Junction surfaces and point-like junctions

**Status: proposed 2026-10-06 from the backlog and the human (2026-10-06: "Some of the junctions still operate like a point, so I will try and find them").**

## Why
Several junction problems from Deck drives are still open, all in the junction surface and
its arms:
- some junctions still behave like a point: roads and traffic meet at one spot instead of
  a polygon (the human is collecting locations);
- a curb stands inside a junction where a curved road joins (2026-10-03);
- terrain shows through some junction surfaces: 47 of 1,936 junctions by
  `test_junction_terrain.gd`, the big ones in cuttings or at tunnel mouths (n14141327481
  +10.5 m, n472497779 +10.7 m, n472558217 +2.9 m);
- "junctions that extend out awkwardly" (2026-10-02), which may share the cause.

## What Changes
- **Find them.** A debug report (`--junction-report`) lists junctions whose polygon is degenerate
  (area under 4 m² with three or more arms), whose arms meet at the node with no trim, or whose
  surface has terrain above it, with x, z for each. Start from the human's locations when they
  arrive.
- **Point-like junctions** get a real polygon: arms trimmed back by their half widths, the
  junction builder fed the trimmed ends, and lanes connected across it. The likely causes are
  junctions skipped by `cluster_junctions`, or nodes tagged fork or merge that aren't.
- **Curbs** from `barriers.py` are cut back to the junction polygon at every arm, curved ones
  included.
- **Terrain under junctions** is flattened in the importer under the junction polygon as well as
  under the edge ribbons (`pack.py`), so junctions in cuttings stop showing ground.
- **Not in this change:** new junction types (roundabouts) or signal changes.

## Impact
- Affected specs: `road-network` (ADDED: Junction Surfaces Cover Their Arms).
- Affected code: `tools/osm_import/cluster.py`, `forks.py`, `barriers.py`, `pack.py` (terrain
  under junctions); `game/world/roads/junction_builder.gd`, `game/world/traffic/lane_graph.gd`;
  the testbed (`--junction-report`); `test_junction_terrain.gd` threshold tightened; pack
  re-exported.
- Overlaps: `add-road-shoulders` 1.4 touches ground gores near motorway junctions; land that
  first or coordinate.
