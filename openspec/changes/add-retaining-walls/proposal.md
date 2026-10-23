# Change: Retaining walls where the ground rises beside a road

**Status: proposed 2026-10-23 (human, issue #167 at Metcalfe under the 417, after the road
edge fix: "the tire trap here is gone, the the lower sidewalks are a bif iffy i think in real
life the under bridge has concrete walls that come straight down"; and: "The under bridges
should probably have cement walls that go straight down on the sides of the tunnel. This
would keep the hills on each side from going over the road.")**

## Why
Where a street passes under a bridge, or runs through a cutting, the ground beside it rises
steeply: to the embankment the deck sits on, or to the street above. Today that rise is the
terrain itself, a grass slope that starts at the sidewalk's outer edge (or the road's edge)
and climbs at whatever angle the 4 m terrain grid gives it. Under the 417 at Metcalfe it
reads as hills spilling onto the sidewalks, the sidewalks look sunk into them, and with a
steep enough slope the grid's interpolation still pulls ground over the road's edge. Real
underpasses and cuttings in Ottawa have vertical concrete retaining walls there.

## What Changes
- **The importer finds wall lines.** Along every ground-level road, it walks the outer edge
  of what the road carries beside it: the sidewalk's outer edge where there is one, the
  shoulder's or the road's edge where not. Every 2 m along that edge it samples the
  finished terrain at 4 m out, perpendicular to the road, away from it. Where that sample
  stands more than `wall_min_m` (1.0 m) above the edge and the rise is steeper than
  `wall_slope` (1 m up for every 1.5 m out), that stretch becomes a retaining wall line.
  The numbers are the spec's (see `specs/road-network/spec.md`).
  - Short gaps between wall stretches on one side are joined; stretches shorter than
    `wall_min_length_m` (6 m) are dropped.
  - A wall's top is the ground behind it; under a bridge deck it is the lower of that and the
    deck's soffit (the wall meets the deck, as an abutment does, and never stands above it).
  - Any way that leaves the road through the wall line breaks it: junctions, side streets,
    driveways and paths. A wall never crosses a way.
- **The terrain steps at the wall.** In front of the wall (between it and the road), the
  ground is held at the road's or sidewalk's level; behind it the ground is left as it is.
  The step is the wall's face, so no slope reaches the road.
- **The game draws the walls.** Concrete (the bridge piers' material), straight down from the
  top to the ground in front, with collision, in the chunks they cross. They are written to a
  new optional file, `retaining_walls.v0.json`, one entry per wall in the barrier shape (`id`,
  `edge_id`, `points`, `height_m`) plus `tops_m`. The game builds them with the barrier code
  (streaming, LODs, collision).
  - **Older games.** A game from before this change doesn't know the file and ignores it: it
    shows the stepped ground without walls, and never builds a wall at the wrong height.
    `barriers.v0.json` and its kinds don't change, so no older reader sees `tops_m`.
  - **Height per point.** A wall's top follows the ground behind it or a deck's soffit, so
    each wall carries `tops_m`: one number per entry of `points`, the wall's height above that
    point (a point is the wall's foot, on the ground in front). `height_m` is required and is
    the tallest of them (for bounds and LOD; the wall itself is built from `tops_m`).
  - Between points the top is interpolated linearly along the segment, like the points
    themselves. Where the game splits a barrier at a chunk boundary (`BarrierBuilder`'s chunk
    split), the cut point's top is interpolated the same way, so the two halves meet.
  - A wall without `tops_m`, or with a `tops_m` of a different length from `points`, is
    rejected by the pack validator and skipped by the game with a warning.
- **Where it shows:** every street under the 417 (Metcalfe, Elgin, O'Connor, Kent, Bank,
  Bronson), the Laurier and Mackenzie King approaches, and any cutting the scan finds.
- **Not in this change:** decorative wall caps, graffiti or posters on the walls (a tone
  pass could add them), noise walls along the motorway, retaining walls around buildings and
  parking lots.

## Impact
- Affected specs: `specs/road-network/spec.md` (ADDED: Retaining Walls).
- Affected code:
  - `tools/osm_import/` (a new `walls.py` after the terrain and bridges; terrain held in front
    of walls; the walls written to `retaining_walls.v0.json`);
  - `docs/pack-format/retaining_walls.schema.v0.json` (new; `tops_m` required, the same length
    as `points`), with the pack validator checking it;
  - `game/world/barriers/barrier_builder.gd` (`Barrier.tops_m`; a loader for
    `retaining_walls.v0.json`; split at chunk boundaries with the points; the wall mesh: a
    quad strip from each point up by its top, with a top face);
  - tests on both sides; the proving ground regenerated (it has a street under the motorway,
    Park Road); the Ottawa packs re-exported.
- `EdgeDropReport` and a new count in the validation report (wall metres per district) show
  the effect.
- Before and after screenshots at Metcalfe under the 417. Deck benchmark at the same spot
  (a few hundred more triangles per chunk where there are walls).
