# Change: The ground under and around junctions follows the junction, so road edges hold

**Status: proposed 2026-10-23 for a fresh session (Fable), after a day of tuning on
`fix/road-edge-drops` (Claude) traded one terrain defect for another. The human: "Create a
plan for Fable to try in a fresh session." Read `design.md` first: it has the numbers, what was
tried, and why tuning alone did not get there.**

## Why
Driving off a road's edge drops a wheel into the grass in about 1,900 places in Centretown
alone: the ground just past the edge sits more than 25 cm below the road. The human drove a
build with most of those removed and called it "much better, I am sticking a lot less" (issue
#167: "the tire trap here is gone"). That build also put grass up through 147 junction
surfaces (one by 1.09 m, where Metcalfe meets its ramp under the 417), left collision up to
3 m above the ground beside Metcalfe under the 417, and lifted sidewalks up embankments (4.6 m
at Metcalfe, 11 m in Gatineau). It was not shipped.

The root cause is the importer's terrain rule: each 4 m terrain cell takes the height of the
nearest road or path (with "a lower surface nearby wins" on top). At a junction whose arms sit
at different heights, the corner between them can only follow one arm: fix the trap on one and
the other's corner pokes up. No distance setting removes that; the junction needs ground of its
own.

## What Changes
- **Junction ground.** The importer flattens the terrain under each junction's surface to the
  surface itself (its outline and per-vertex heights, as the game's `JunctionBuilder` draws
  it), and blends from that outline to the arms' ground, instead of letting the nearest arm
  win in the corners.
- **Road edges own their ground.** With junction corners owned by the junction, a road owns the
  ground in its own flat zone ahead of any nearer path, and a lower road or path only lowers the
  ground it is actually over (the first fix on `fix/road-edge-drops`, kept).
- **Bridge ends and decks.** The under-deck lowering stops short of where a deck meets the
  ground, roads passing beneath a deck keep their beds, and roads at deck height don't raise
  the ground under the deck (pieces from `fix/road-edge-drops` and `wip/road-edge-experiments`,
  re-checked against the new junction ground).
- **Sidewalks.** A sidewalk buried a little (up to 0.5 m) is lifted onto the ground; buried
  deeper, it keeps its height and the ground is cut along it, never under a road.
- **One command to judge it.** `scripts/terrain-trial.sh <district>` exports a district, runs the
  wheel-trap scan, the junction test and the Metcalfe test, and puts the locked pack back.
- **The junction check measures the drawn surface.** `JunctionReport.terrain_above` samples the
  triangulated outline the game draws instead of a fan from the node's height, which at a
  clustered junction is not what is drawn (design.md, lesson 2).
- **Not in this change:** retaining walls (`add-retaining-walls`, #168), which handle a steep
  bank beside a road once the ground at the edge is right.

## Impact
- Affected specs: `specs/road-network/spec.md` (ADDED: Road Edges Without Wheel Traps).
- Affected code: `tools/osm_import/pack.py` (terrain: `_distance_field`, `flatten_roads`,
  `_junction_corners` or its replacement, `clamp_under_decks`, `restore_road_beds`,
  `lift_buried_paths`, `cut_under_deep_paths`), `tools/osm_import/__main__.py` (order of the
  terrain passes); `game/world/roads/edge_drop_report.gd` and its test (already on the branch);
  `game/world/roads/junction_report.gd` (the surface sampled), `tools/osm_import/junctions.py`
  (new: the outline port) and `game/world/build/junction_outline_dump.gd` (new: the fixture);
  the proving ground regenerated; the three Ottawa districts re-exported and released (next
  versions: Centretown 0.5.1, the Glebe 0.2.1, Hintonburg 0.2.1; 0.5.0 and 0.2.0 exist as
  releases but are superseded and must not go in the lock).
