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
  shoulder's or the road's edge where not. Wherever the finished terrain a short way past
  that edge stands more than `wall_min_m` (1.0 m) above the road and rises faster than a
  bank can (steeper than `wall_slope` 1:1.5), that stretch becomes a retaining wall line.
  - Short gaps between wall stretches on one side are joined; stretches shorter than
    `wall_min_length_m` (6 m) are dropped.
  - Under a bridge deck, the wall's top is the deck's soffit (the wall carries the deck, as
    an abutment does); elsewhere it is the ground behind it.
  - Junctions, driveways and paths that leave the road through the wall break it: a wall
    never crosses a way.
- **The terrain steps at the wall.** In front of the wall (between it and the road), the
  ground is held at the road's or sidewalk's level; behind it the ground is left as it is.
  The step is the wall's face, so no slope reaches the road.
- **The game draws the walls.** Concrete (the bridge piers' material), straight down from the
  top to the ground in front, with collision, in the chunks they cross. They are written as a
  new barrier kind `retaining_wall` in `barriers.v0.json` with a top height per point, so the
  existing barrier streaming, LODs and collision carry them.
- **Where it shows:** every street under the 417 (Metcalfe, Elgin, O'Connor, Kent, Bank,
  Bronson), the Laurier and Mackenzie King approaches, and any cutting the scan finds.
- **Not in this change:** decorative wall caps, graffiti or posters on the walls (a tone
  pass could add them), noise walls along the motorway, retaining walls around buildings and
  parking lots.

## Impact
- Affected specs: `road-network` (ADDED: Retaining Walls).
- Affected code:
  - `tools/osm_import/` (a new `walls.py` after the terrain and bridges; terrain held in front
    of walls; `barriers.py` writes the new kind; schema `barrier.schema.v0.json`);
  - `game/world/roads/barrier_builder.gd` (the wall mesh: a quad strip from the top line to
    the ground line, with a top face);
  - tests on both sides; the proving ground regenerated (it has a street under the motorway,
    Park Road); the Ottawa packs re-exported.
- `EdgeDropReport` and a new count in the validation report (wall metres per district) show
  the effect.
- Before and after screenshots at Metcalfe under the 417. Deck benchmark at the same spot
  (a few hundred more triangles per chunk where there are walls).
