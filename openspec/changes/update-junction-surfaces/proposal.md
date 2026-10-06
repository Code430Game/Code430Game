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
- "junctions that extend out awkwardly" (2026-10-02), which may share the cause;
- three-way junctions turn into a "ball" or a "C" (issues #78 and #79, 2026-10-06 Deck drive):
  - #78, Colonel By Drive at x 998, z 1041 (junction `n901218147`), where the two-way road
    divides into one-way carriageways: "junction turns into ball";
  - #79, a parking aisle off Graham Avenue at x 1098, z 935 (junction `n6020506072`): a wedge
    of asphalt with a sign standing in it.

  The X-intersection case was fixed by `update-cluster-junction-arms` (fa34b3d); T and Y
  junctions were not.

## What Changes
- **Find them.** A debug report (`--junction-report`) lists junctions whose polygon is degenerate
  (area under 4 m² with three or more arms), whose arms meet at the node with no trim, or whose
  surface has terrain above it, with x, z for each. Start from the human's locations when they
  arrive.
- **Three-way junctions follow their roads.** Where a road runs straight on through a T or Y,
  the outline follows its edges instead of pushing a corner into the grass on one side or back
  across the road on the other. Narrow Y splits and divided carriageways whose ribbons touch are
  covered without crossing outlines. A road dividing into one-way carriageways has its
  carriageways start on its own lanes, so the surface does not pinch (the importer's
  `shape_splits`). Details in `design.md`.
- **Point-like junctions** get a real polygon: arms trimmed back by their half widths, the
  junction builder fed the trimmed ends, and lanes connected across it. The likely causes are
  junctions skipped by `cluster_junctions`, or nodes tagged fork or merge that aren't.
- **Curbs** are cut back to the junction polygon at every arm, curved ones included. The game
  does the cut when it loads the pack (`BarrierBuilder.clip_curbs`), since only it knows the
  junction outlines exactly.
- **Terrain under junctions** is flattened in the importer under the junction polygon as well as
  under the edge ribbons (`pack.py`), so junctions in cuttings stop showing ground.
- **Not in this change:** new junction types (roundabouts) or signal changes.

## Impact
- Affected specs: `road-network` (ADDED: Junction Surfaces Cover Their Arms).
- Affected code: `tools/osm_import/forks.py` (splits), `pack.py` (terrain into junction
  corners), `road_classes.json`, `pipeline.py`; `game/world/roads/junction_builder.gd`, new
  `junction_report.gd`, `game/world/barriers/barrier_builder.gd` (curb clipping),
  `game/world/packs/map_pack.gd`; the testbed (`--junction-report`) and a headless
  `world/build/junction_report.gd`; `test_junction_terrain.gd` threshold tightened; golden
  fixture and pack re-exported. `cluster.py` and `lane_graph.gd` needed no change.
- Overlaps: `add-road-shoulders` 1.4 touches ground gores near motorway junctions; land that
  first or coordinate.
