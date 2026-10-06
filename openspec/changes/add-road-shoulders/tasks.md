## 1. Importer
- [x] 1.1 Shoulder widths per class; motorway, trunk and link ribbons and decks widened outside the outer lanes; edge lines at the lane edge; tests
- [x] 1.2 Parapets at the shoulder edge; tests. Found the "half hexagon" walls' cause: a parapet stepped out around any sidewalk near the deck, including a street's sidewalks passing 6 m under it, so it bent out around them. Parapets now only make room for walkways at deck level running along the deck
- [x] 1.3 Re-export the Ottawa pack; golden fixture updated
- [ ] 1.4 Gaps still open after 1.1 and 1.2: carriageways of one structure more than a shoulder apart (up to `infill_max_m`) get a concrete floor at deck height; ground gores between a motorway and its ramps paved; tests

Notes (2026-10-05):
- Shoulders: motorway and trunk 1.0 m left, 2.5 m right; links 0.6 / 1.5; two-way roads get the right width both sides; a tagged `width` gets none. `width_m` is the paved width; `shoulder_left_m` and `shoulder_right_m` are inside it. Lanes, lane lines, edge lines and spawn points use the carriageway (`RoadEdge.carriageway_m()` and `carriageway_offset()`).
- Where a shoulder would spread over another road at a different height (a ramp alongside through an interchange), it is dropped for that edge (`shoulders.py`, after elevation): 62 of 170 in the Ottawa pack. Forks line a ramp up with the through road's lanes, not its paved edge.
- Sound walls measure their house range from the lanes, so a shoulder doesn't pull houses into range (one had appeared over Metcalfe).

## 2. Game
- [x] 2.1 Road and bridge meshes draw shoulders (they follow `width_m`); collision follows; terrain carved under; before and after screenshots at the 417 over Metcalfe

## 3. Verification
- [ ] 3.1 Deck benchmark against main
- [ ] 3.2 Human drives the 417 and walks under it on the Deck
