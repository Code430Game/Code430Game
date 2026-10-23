# Design: junction ground

## Where to start
- Branch from `fix/road-edge-drops` (commits 7af63cb, 0df9748): the edge drop scan
  (`EdgeDropReport`, `game/world/build/edge_drop_report.gd`) and its test, the importer's first
  fixes, and the proving ground regenerated with them. Restore `test_junction_terrain.gd`'s
  `MAX_POKING_SHARE` to 0.01 first: 0df9748 raised it to 3% as a stopgap, and this change's
  point is to not need that.
- `wip/road-edge-experiments` holds the day's later attempts, for reference, not to merge.
- Measure with `scripts/terrain-trial.sh centretown` (about 4 minutes; GODOT_BIN, the OSM cache
  at `CODE430_OSM_CACHE`, the Location-OttawaOnCa repo beside this one).
- Watch out: `scripts/fetch-packs.sh` trusts its stamp files in `packs/.fetched/`. If you copy a
  pack into `packs/` by hand, it will say "ok" and leave your copy there, and local CI's own
  fetch can swap packs mid-session. The trial script clears the stamp when it restores. (Worth
  fixing on its own: check the files, not only the stamp.)

## The bar (all at once, Centretown unless noted)
| Check | Main today (Centretown 0.4.0) | Must be |
|---|---|---|
| Wheel traps (EdgeDropReport spots) | 1,889 | under 700 (the shipped-not build had 438) |
| Junctions with terrain through the surface (`test_junction_terrain`) | 15 of 2,198 (0.7%), worst 0.18 m | at most 1%, worst at most 0.5 m |
| Metcalfe under the 417 (`test_terrain_collision`) | passes (ground about 66.8 m, road 67.4 m) | passes |
| Proving ground streets (`test_edge_drop_report`) | — | no street drop over 0.5 m |
| Sidewalk points lifted over 0.5 m | 0 | 0 |
| Glebe, Hintonburg wheel traps | 819, 748 | well down, no new junction pokes |
| Tool tests, game tests, local CI | green | green |

Then the Deck: the human drives the spots below.

## What the day found (numbers on Centretown)
| Variant | Traps | Junction pokes | Metcalfe |
|---|---|---|---|
| main | 1,889 | 15 | ok |
| first fix (7af63cb: covers only within ribbon + 0.5 m, deck-end fence, bed restore, unlimited sidewalk lift) | 438 | 147, worst 1.09 m | step (68.0–70.6 m) |
| lower road keeps its 4 m zone (old rule) + bed restore checked under decks | 1,538 | 17 | ok |
| lower road keeps 2 m | 793 | 51 | step |
| lower road keeps 4 m only within 20 m of a junction node | ~1,400 | 17 | ok |
| no junction protection, junction corners at full cover, bed restore checked under decks | 1,024 | 51 | ok |
| 0df9748 clean-up + strict under-deck + lowest bed + fence at ground ends | 471–618 | 125–146 | step at one point |

Lessons:
1. Most traps the first fix removed were within 20 m of a junction: corners between arms at
   different heights. The same corners are where grass pokes up. It is one problem seen from two
   arms; it needs the junction surface's own heights under it.
2. The deck-end fence (no lowering within one cell inside a deck end) removes pits beside bridge
   approaches (Bridge Street and Mill Bridge Road on the proving ground; the human saw the
   river get better). Near the 417's abutments it leaves refill standing; with bed restore it
   also raised ground onto Metcalfe. Match fences to where a deck meets the ground (`b.ends`),
   and let a road passing beneath a deck own its bed (`_lowest_bed` in the wip branch).
3. Bed restore must not use a deck-height road's bed under the deck (the 417's ground approach
   segment at 74 m sits right beside Metcalfe at 67.4 m), and "under a deck" must mean alongside
   it, not past its ends (`_under_decks` in the wip branch).
4. The unlimited sidewalk lift carried a Metcalfe sidewalk 4.6 m up the 417's embankment (the
   human's screenshot) and others up to 11 m. Cap it (0.5 m) and cut the ground along deeper
   ones instead (`cut_under_deep_paths`, in 0df9748).
5. The "triangulation failed" errors in reports are 2D (`canvas_item_add_polygon`: the minimap
   or full map), not holes in the world. Separate, cosmetic.

## Approach for junction ground
- The game builds each junction's outline and per-vertex heights in `JunctionBuilder`
  (`game/world/roads/junction_builder.gd`). The importer has `_junction_corners` (segments into
  each corner at the arms' mean height), which is an approximation of the same surface.
- Do one of:
  - **(a) Port the outline to the importer.** Build the same polygon and heights in Python,
    flatten every terrain cell inside it (plus `FLAT_MARGIN_M`) to the surface interpolated at
    that cell, and let road segments own only what lies outside junction outlines.
  - **(b) Export it from the game.** Run `JunctionBuilder` at import time (headless Godot) and
    read its outlines back. Exact, but couples the importer to Godot.
  - (a) is the likelier fit: the importer is pure Python today. Keep a test that the Python
    outline matches the game's on the proving ground's junctions (within the 4 m grid).
- Order of passes stays: carve bridges, water, buildings; pedestrian heights; flatten roads and
  junctions; then bridges are built, the under-deck clamp, bed restore, sidewalk lift and cut.
- Re-check each lesson above after junction ground goes in; some workarounds may no longer be
  needed.

## Places to look at on the Deck when it's done
- Metcalfe under the 417 (x 610–620, z 1000–1025): the ramp junction, the sidewalks, the abutment.
- Colonel By Drive / Daly Avenue (211, −469); MacLaren Street service road (765, 109); Raymond
  Street by the 417 ramp (−622, 1638); Chamberlain / Percy (−266, 1602).
- Nelson Street at Somerset (1303, −310): the original sidewalk-corner trap.
- Mill Street by the pub and the Portage / Booth area: the human calls these really complex (a
  parking lot, a path under the roadway, the bridge exits).
- The Mackenzie King Bridge: its walkway to the Rideau Centre and the DND building's upper
  entrances is a real elevated path, correct as it is.
