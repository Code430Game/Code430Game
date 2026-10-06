## 1. Importer
- [x] 1.1 Shoulder widths per class; motorway, trunk and link ribbons and decks widened outside the outer lanes; edge lines at the lane edge; tests
- [x] 1.2 Parapets at the shoulder edge; tests. Found the "half hexagon" walls' cause: a parapet stepped out around any sidewalk near the deck, including a street's sidewalks passing 6 m under it, so it bent out around them. Parapets now only make room for walkways at deck level running along the deck
- [x] 1.3 Re-export the Ottawa pack; golden fixture updated
- [x] 1.4 Gaps still open after 1.1 and 1.2: carriageways of one structure more than a shoulder apart (up to `infill_max_m`) get a concrete floor at deck height; ground gores between a motorway and its ramps paved; tests
  - 2026-10-06, built on `update-shared-deck-heights`, so the decks either side of a gap are at one height.
  - Deck infill (`bridges._add_infill`):
    - Where two road decks of the same layer and level (within 0.3 m) leave a gap between their deck edges of up to `infill_max_m` (8 m), a strip runs down the middle of the gap, overlapping each deck by 0.3 m.
    - Strips are ordinary deck strips in `bridges.v0.json` (`source` `infill:<a>:<b>`), so the game draws them as deck slabs with collision, and the terrain under them is lowered like under any deck. No game change was needed.
    - Pairs are found across bridge groups, because the grouping only joins decks within 3 m. Each strip joins the longer deck's bridge.
    - A gap that only opens past the other deck's end is not filled.
  - Ottawa pack: 32 strips, 1,151 m in all:
    - Mackenzie King Bridge, 194 m and 51 m with a 4–5.5 m gap, plus 39 m;
    - Alexandra Bridge, 396 m and 172 m;
    - Portage Bridge, 78 m;
    - the Plaza Bridge ramps;
    - short pieces on the 417 decks (Metcalfe 21 m, Elgin 6–8 m).
  - Parapets (`barriers.py`, new `infill` argument): a deck edge that faces an infill strip has floor beyond it, so no parapet stands there. Parapet runs went from 90 to 78; the outer ones stay.
  - Ground gores (`gores.py`, after `trim_shoulders`):
    - Ground carriageways of `gore_classes` (motorway, trunk and links) running the same way get the same strip down the gap, from just past the fork until the gap passes 8 m.
    - Opposing carriageways across a median are never paired.
    - Gores are written to `road_graph.v0.json` as `gores` (optional in the schema). The terrain is flattened under them like under roads.
    - The game draws them as asphalt in the road mesh, with collision, 1.5 cm under the ribbons they meet.
    - Ottawa pack: 11 gores; the longest is 66 m, by Metcalfe (621, 953).
  - Tests:
    - `test_osm_infill.py`: a 5 m gap floored at deck height over the whole span; nothing at 10 m or across layers; facing parapets gone and outer ones kept; a splitting ramp floored up to the limit.
    - `test_osm_gores.py`: an off-ramp's gore after the fork and within the limit; no gore across a median or for other classes; the terrain footprint includes it.
    - `test_road_mesh_builder.gd`: a gore drawn facing up, just under the ribbons.
  - Screenshots:
    - Mackenzie King Bridge from above: the walled gap between the decks, showing the ground below, is now one concrete floor with the facing parapets gone.
    - The ramps by Metcalfe: the grass wedge between them is paved up to the limit.
    - Elgin: the infill there is too small to see at that distance.

Notes (2026-10-05):
- Shoulders: motorway and trunk 1.0 m left, 2.5 m right; links 0.6 / 1.5; two-way roads get the right width both sides; a tagged `width` gets none. `width_m` is the paved width; `shoulder_left_m` and `shoulder_right_m` are inside it. Lanes, lane lines, edge lines and spawn points use the carriageway (`RoadEdge.carriageway_m()` and `carriageway_offset()`).
- Where a shoulder would spread over another road at a different height (a ramp alongside through an interchange), it is dropped for that edge (`shoulders.py`, after elevation): 62 of 170 in the Ottawa pack. Forks line a ramp up with the through road's lanes, not its paved edge.
- Sound walls measure their house range from the lanes, so a shoulder doesn't pull houses into range (one had appeared over Metcalfe).

## 2. Game
- [x] 2.1 Road and bridge meshes draw shoulders (they follow `width_m`); collision follows; terrain carved under; before and after screenshots at the 417 over Metcalfe

## 3. Verification
- [x] 3.1 Deck benchmark against main (2026-10-05, idle Deck, `--benchmark=40 --autodrive --preset=deck`, two runs each: before avg 12.64 / 12.58 ms, p99 25.0 / 23.7; after 12.63 / 12.90 ms, p99 25.0 / 25.0. Within run-to-run noise.)
- [ ] 3.2 Human drives the 417 and walks under it on the Deck
