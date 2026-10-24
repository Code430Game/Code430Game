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
