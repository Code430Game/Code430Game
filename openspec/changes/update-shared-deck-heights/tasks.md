## 1. Importer
- [x] 1.1 Group touching carriageways of one structure; shared height profile with blends into the approaches; tests on a two-deck fixture with a 0.5 m step
- [x] 1.2 Same on the ground for overlapping motorway carriageways; shoulder trimming re-run; counts before and after in the PR
- [x] 1.3 Re-export the Ottawa pack; golden fixture; screenshots at the Mackenzie King Bridge (x 517, z -523) and the 417 over Metcalfe

Notes (2026-10-06):
- `elevation._share_heights` runs at the end of `apply_elevation`, so `trim_shoulders` (next in the pipeline) already sees the shared heights. It works per vertex, not per group. A vertex is shared when another carriageway runs beside it within the gap and within `max_step_m` (0.8 m) of its height; a bigger difference is a real level change (a ramp climbing away) and is kept.
- Carriageways here are bridge decks and ground roads of `ground_classes` (motorway, trunk and their links). Decks pair with decks of the same layer and also with ground carriageways: near bridge ends one carriageway is often still on its deck while the other is already on the ground. Keeping the two kinds apart left a 0.7 m jump at a 417 deck end.
- Every shared vertex takes the highest of its partners' heights, never the mean, so no deck drops into the clearance over the road below. The exception is ground roads inside a deck footprint, which take the lowest, so clearance under a deck never shrinks. Mixing rules (decks highest, ground mean) left 0.4 m steps where three carriageways run side by side (two decks and a ramp, or a motorway and its on-ramp), and `test_terrain_collision` caught the terrain over the on-ramp at (817, 914).
- The rule repeats until nothing moves (at most 8 rounds), so a raise reaches the third carriageway too.
- No span vertex is ever lowered and tunnels are left alone.
- After sharing, the change fades out over `blend_m` (30 m) along every connected road. Then the shared vertices are pinned, raised to each other's grade where two disagree, and the grade limits run again over the rest.
- Deck gap: "touching" uses the parapets' `parapet_shared_deck_gap_m` (3.5 m), not 1 m. On the Mackenzie King Bridge the road ribbons are 1.4–2.4 m apart, but the decks are widened over the sidewalk between them and touch along the whole span; the parapets already treat that as one deck. Wherever no wall stands between two decks there is now no step either.
- Medians (`barriers.py`): with the inner shoulders restored, opposing 417 carriageways' paved ribbons overlap by up to 2 m, and the median needed a gap of at least 0 between the ribbons. It is now measured from the lanes, so the median stays and no guardrail takes its place.
- Ottawa pack:
  - 82 deck and 60 ground vertices shared; the largest step closed is 0.79 m.
  - Mackenzie King Bridge: the 0.42–0.48 m step is now under 5 mm at every vertex.
  - **Shoulders dropped: 62 → 42 of 170.**
  - Clearance: none of the 138 deck crossings lost clearance.
  - Edges over grade: 15 → 12. Six are within grade now; three are new:
    - `w76419866.0`, secondary, 10.5 % (limit 6 %);
    - `w76422506.0`, motorway, 5.9 % (limit 4 %);
    - `w76445665.0`, link, 6.7 % (limit 6 %).
  - The steepest grade in the pack is unchanged at 0.19.
  - Medians 2,000 → 2,088 m.
- A baseline re-export of main with the same cache was byte-identical to the committed pack, so every pack diff here comes from this change.
- Screenshots:
  - Mackenzie King Bridge, looking west from the west deck: the raised side face between the decks is gone, flush after.
  - 417 over Metcalfe: unchanged, median continuous; its carriageways were already level there.

Follow-up 2026-10-07 (`fix/shared-heights`, after the human saw ramps "bowed with just the ends
elevated"):
- **Rule:** ground carriageways merge down. Sharing is one pass, with no rounds to run out. Vertices
  pair at matching stations, decks excluded, or snap within `loose_snap_m`; the rest follow their
  partner through the grade pass.
- **Guardrails:** none in paved gores, and medians are kept out of every carriageway's lanes.
- **Ottawa against main** (857ac35):
  - parallel steps over 10 cm: 65 → 29;
  - importer step left: 0.571 → 0.355 m;
  - edges over grade: 14 → 9;
  - OSM vertices raised far from decks: 58 → 9;
  - doubled guardrails at the 417 merge: 2 → 0;
  - medians in lanes: 10 → 0.

## 2. Verification
- [ ] 2.1 Human drives the Mackenzie King Bridge on the Deck
  - 2026-10-21 Deck: not done: the Mackenzie King Bridge wasn't revisited.
  - 2026-10-22 Deck (Centretown 0.3.0): the human "got mostly across it. Before accidentally holding R3"; asked whether the joined carriageways felt right (no step) up to there.
