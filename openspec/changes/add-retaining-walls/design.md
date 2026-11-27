# Design: retaining walls

## Handoff from update-junction-ground (2026-10-23)
What the junction-ground session leaves for this one.

- **Where the walls go.** After the junction ground (Centretown 0.5.1), the deep drops at road
  edges are banks and abutments: the 417 landing over the Nicholas Street ramps (x 105-130,
  z 1300-1350), the 417 beside Metcalfe (x 610-625, z 1000-1025) and Bank, the Alexandra Bridge
  (x -530, z -1030) and Portage Bridge (x -1376, z -69) abutments, O'Connor at the escarpment
  (x -279, z -140), and sidewalks at the foot of embankments (Highway 417 at x -578, z 1662).
  `EdgeDropReport` lists them deepest first; the Deck drive confirmed Metcalfe already looks
  "like the start of walls" where the under-deck lowering meets the abutment refill.
- **Measure in seconds, not minutes.** `tools/terrain_replay.py` captures a district once
  (export with the road passes stubbed; the carved chunks, graph and bridges pickled) and
  replays flatten, the sidewalk lift and cut, the under-deck lowering and the bed restore in
  about 25 s, then counts wheel traps and junctions with terrain through the drawn surface
  with Python ports of the game's two reports (within three of the game's own numbers). Holding
  the terrain in front of a wall (task 1.2) is a road pass: add it to `Replay.run` and iterate
  there, then confirm with `scripts/terrain-trial.sh` and the game's reports.
- **The bar is the real districts.** The proving ground is only a guard (it passed every
  variant while Centretown swung from 590 to 1,300 traps); judge on Centretown, then the Glebe
  and Hintonburg. The bar, from `update-junction-ground`'s design.md: under 700 Centretown
  wheel traps; at most 1% of junctions with terrain through the drawn surface, none over
  0.5 m; Metcalfe under the 417 passing; no proving-ground street drop over 0.5 m; the Glebe
  and Hintonburg with no new junction pokes. Where that change left Centretown, to beat not
  to match: 669 traps, 16 junctions poking (0.7%, worst 0.16 m); the Glebe 294 traps and 3
  junctions, Hintonburg 208 and 6.
- **Versions.** A new pack file (`retaining_walls.v0.json`) is a minor bump: Centretown 0.6.0,
  the Glebe and Hintonburg 0.3.0 (`python -m pack_tools version check` confirms). The pack
  repo's `code430.json` pins the game commit the packs were exported from; its PR, tags and
  the game's `packs.lock.json` follow the order in `update-junction-ground`'s tasks 4.1.
- **Two trade-offs to keep.** The terrain under a junction may sit up to 15 cm below an arm's
  ribbon (`JUNCTION_FLOOR_SLACK_M`); a wall in front of a junction corner must not raise the
  ground above that. And the sidewalk cut (`cut_under_deep_paths`) never digs under a road's
  ribbon but does within its margin: a wall behind a sidewalk at the foot of an embankment
  replaces that cut, so the cut should stop where a wall starts.
- **Known spots that are data, not terrain.** The walkway down to Colonel By Drive at Daly
  (#172) ends four metres in the air because its steps are missing from OSM and the importer
  gives a node shared by an elevated path and a ground way one height; a pedestrian-elevation
  fix, not a wall.

## What this session found (2026-10-23, Fable)
Measured with `tools/terrain_replay.py` on a Centretown capture (40 s a variant), then with
`scripts/terrain-trial.sh` and the game's own reports on the exports.

- **A 4 m probe from a bare road's edge never finds a bank.** Every ground road's own
  grading keeps the terrain at its level for `FLAT_MARGIN_M` (4 m) past its edge and blends it
  over `SHOULDER_M` (3 m) more; under a deck `restore_road_beds` gives the road its shoulder
  too, so the bank beside Metcalfe Street's west side (no sidewalk in OSM) starts 7 m from the
  edge. The spec's probe (4 m out from the outer edge) found walls only beside sidewalks, where
  a higher road's zone or a deck's abutment refill reaches within 4 m. So the scan walks out
  from the outer edge for the first metre that climbs more than 1:1.5, up to `reach_m` (8 m):
  where the climb starts within `probe_m` the wall stands at the edge; further out it stands
  where the climb starts. The delta spec says so now. Centretown: 160 walls / 2.6 km with the
  edge-only probe, 279 walls / 6.2 km with the walk; Metcalfe under the 417 gets walls on both
  sides (east at the sidewalk's edge, 4.6-6.2 m to the soffit; west at the bank's foot).
- **Ways above or below the edge don't break a wall.** The 417's ground approach ends 7 m from
  Metcalfe's sidewalk, and its ribbon end counted as "a road leaving the road": no wall at the
  one place the change is for. A road, path or junction only breaks the wall within `LEVEL_M`
  (2.5 m) of the edge's height.
- **The hold must respect the road's own rule and other roads' grading.** First attempts cost
  wheel traps (669 -> 679): cells lowered just past another road's flat margin pulled the
  interpolated ground at that road's edge down (a 5.5 m drop on the 417 beside Bronson), and a
  sidewalk a little below its road pulled the ground between them down (Nelson, King Edward).
  Now: in front of the wall the ground follows the higher of the road and the sidewalk and keeps
  off other roads' ribbons plus 1.5 m (EdgeDropReport reads to 1 m); behind the wall (held only
  where the wall stands at a sidewalk's edge, so the bank cannot poke through the sidewalk) it
  keeps off other roads' whole grading zone (7 m); junction zones and building footprints are
  never touched; nothing is raised over another road's bed. Sidewalks more than 0.75 m off
  their road's level are some other street's and are ignored.
- **Walls neither make nor fix wheel traps, as expected.** They answer rises; the traps are
  drops. Centretown by the game's reports: 668 wheel traps (669 before), 16 of 2,198 junctions
  with terrain through the drawn surface (0.7%, worst 0.16 m, as before), Metcalfe under the 417
  passes. The tallest walls (15-18 m) stand at the Alexandra Bridge approach and Commissioner
  Street under the Portage Bridge's embankment, where the DTM's real embankments are.
- **The proving ground has no bank for Park Road.** Its viaduct stands on piers over level
  ground, so Park Road gets no wall (rightly). The regenerated pack has 4 walls (62 m) along
  Viaduct Road South and 5 Lane; it is the guard, not the bar.

### After the first Deck look (the same evening)
The human's Deck screenshots showed zigzag walls on the verges beside the 417 near the start,
a wall between a ramp and its mainline, and walls tall enough to drop in behind. Four rules
followed, measured again on the capture:
- **The rise is the spec's.** A 1 m rise at 4 m with any 1:1.5 window between caught every
  shoulder blend up to a higher verge. Now the ground the wall would hold back must stand
  1 m per 1.5 m out above the foot (2.67 m at 4 m).
- **A parallel road's grading zone is not a bank.** The ground within another road's ribbon,
  flat margin and shoulder (7 m) that runs within 40 degrees of this one is its surface or its
  embankment: the mainline beside a ramp, the 417 above its frontage road. A road crossing
  over (the 417 over Metcalfe) still counts, so the underpass walls stay.
- **A bare road's wall is a straight line and holds one cell.** Its foot is the running median
  (9 stations) then mean of where the climb starts, never "at the edge" (the margin there is
  always level), and its top is the ground 4 m behind, capped at 8 m, so a slope above a wall
  shows as a slope and the slot behind a tall wall is gone. Behind a sidewalk the top stays
  the highest ground within two cells (that cell is held down to the foot).
- Centretown: 145 walls / 3.6 km (from 279 / 6.2 km), 667 wheel traps, pokes unchanged; the
  Glebe 25 / 0.4 km and 294 traps, Hintonburg 36 / 0.8 km and 208;
  Metcalfe keeps its walls on both sides. The verges at x 681 and 736 beside the 417 have none.
  The proving ground's four walls along Viaduct Road South were the viaduct ramp's own
  embankment and are gone: it now writes an empty `retaining_walls.v0.json`.

### After the Deck stop (2026-11-24): walls that hold the ground back
The human's verdict at 3.2: the walls are chaotic and not smooth; they got stuck behind one;
some go too high and retain nothing. "The retaining wall should shift the slope: the slope
would go to the retaining wall, the wall would be vertical, and then the slope would continue
at the top of the wall." Measured on the same Centretown capture with the walls as they stood:
at 1,615 of 1,779 wall stations the ground 2 m behind the wall lay more than a metre below
its top. The wall was drawn on a slope that carried on under it as before, with a wedge to
fall into behind it; and its line followed where the climb started, cell by cell.

What changed, and why each part is as it is:
- **The ground is made to fit the wall.** In front of the wall the ground is held at the
  foot (as before); behind it the ground is raised to the wall's top out to `FILL_M`
  (15.5 m), never lowered. So the bank carries on from the top of the wall.
- **A 4 m grid cannot step, so the wall is a block.** Between a low cell and a high cell
  the terrain is a 4 m ramp. If the ramp starts in front of the face the grass climbs the
  wall and spills on the sidewalk; so every cell that touches the face is low, which means
  every cell within one cell's diagonal (5.66 m) behind the line. The ramp then lies behind
  the face, within two diagonals. The game closes it: each wall has a level top reaching
  `cap_m` (11.5 m) back, in the terrain's colour, sinking 0.5 m to its back edge so it runs
  into the raised ground, with both ends closed. Nothing is behind a wall to drop into; a
  player on the bank walks onto the wall's top and to its face.
- **The line is the road's, not the bank's.** The foot runs at the sidewalk's outer edge, or
  4 m from a bare road's edge (where the road's own level margin ends), wherever the climb
  starts; between the two it moves 1 m per 4 m along. The running median of climb starts is
  gone, and with it the review's finding that a joined station pulled the line back to the
  road's edge. A sidewalk up to 8 m from the ribbon is the road's (Metcalfe's west sidewalk
  under the 417 stands 4 m off, and the wall would have covered it) unless another road lies
  between.
- **Tops.** The ground 4 m into the climb; the bank's crest where that is within 2 m above
  (the top is then level with the ground up there); the soffit where the bank climbs to a
  deck. The median of five then the mean of three along the wall, a taper of 1 m per metre
  to the ground at an end, none where the wall carries on along the road's next edge (the
  first try dipped to the ground at every split in a way). After the ground is shaped a top
  is lowered to the ground at the back of its cap where the fill was kept off it (another
  road's grading, a building), so no wall stands above what it holds.
- **Not a wall:** where the cap would cover a lower road, junction or path; a line that
  turns over 30 degrees at a point (the inside of a loop tighter than the offset); a wall
  under 1.5 m at its tallest; the shorter of two walls two roads build along each other.
- **What is left.** Where another road's grading zone reaches the face (the 417's ground
  approaches beside its underpasses) the cells behind the face may not be lowered, or that
  road gets a wheel trap; there the bank still starts at the wall's face, and at a corner of
  the embankment a little in front of it. And a wall's end: the bank beside it comes round
  the end as a slope. Both were so before.

### After the second Deck try (2026-11-27): only walls that hold a bank at the road

The human: it works and is better, but a couple of walls stand on the edge of Parliament Hill
that should not be there. Both were on Wellington Street (9 m and 28 m, about 4 m tall),
where the lawn's bank comes within `reach_m` of the sidewalk for a short way. Behind their
line the ground is level for 4.5 and 5 m before it climbs: nothing to hold at the road, and
the bank runs on both ways without a wall, so the two stood as slabs on a lawn.

- **A verge before the bank.** Measured on every wall of the Centretown capture: the walls
  that work (Metcalfe under the 417, the Alexandra Bridge approach, Lady Grey Drive) have
  ground 0.75 m up within 2.5 m of the line; 42 of 185 had 3.5 m or more of level ground
  first. Rule: no wall where the ground is within 0.5 m of the foot from the line to
  `max_toe_m` (3 m) behind it. `reach_m` stays 8 m: it finds the climb, this says whether
  the climb is the road's.
- **A dip before the bank.** Three walls stood with the ground up to 4 m below the foot just
  behind them (a cutting beside the road, the bank across it). No wall where the ground
  within those 3 m is over 0.75 m below the foot.
- **Judged a stretch at a time.** The first try tested each station: a bank whose foot
  wanders across the 3 m was cut into pieces, and the pieces fell under the minimum (the
  Metcalfe walls lost 4 to 10 m each, one went). A stretch goes when over half its stations
  fail, else it stays whole. Tried first with the place the climb starts (`start`) as the
  measure: that also took banks that rise gently from the line and steepen further back
  (Rideau Street 41 m, Henderson Avenue 40 m), which do hold ground at the road; the
  ground's level does not.
- **Stubs.** 46 of 185 walls were under 10 m, with a cap 11.5 m deep behind each: blocks
  deeper than long. A wall is cut wherever its road's data is split, so the test is on the
  run: walls whose ends meet within `join_gap_m` are one run, and a run under `min_run_m`
  (12 m) is dropped. `min_length_m` stays 6 m for a piece of a longer run.
