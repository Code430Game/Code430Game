# Change: Parking lot layouts and street-side parking

**Status: proposed 2026-10-06 from the backlog (human, 2026-10-05 Deck round: "we probably need to do some more passes with the fill in algorithm"; street-side bays exported but unused since add-parking-lots).**

## Why
- Lot layouts look off in places: stall rows that don't follow the lot, odd gaps, spaces cut
  by the outline.
- 256 street-side parking bays are in `parking.v0.json`, but roads have no parking lane, so a
  car parked there would stand in the travel lane; they get no cars.

## What Changes
- **Lot fill passes** in `parking_lot_builder.gd`:
  - rows follow the lot's long axis per convex piece (split concave lots first);
  - aisles connect to the lot's entrances from the road graph;
  - a second pass fills leftover strips with single rows (`_row_only`);
  - stalls are kept clear of streets (`_clear_of_streets`), walls and trees.
  Start from the human's screenshots of bad lots (they will send them).
- **Street-side parking.** Edges with `parking:lane:*` tags get a parking lane in
  `width_m` (like `shoulder_*_m` in `add-road-shoulders`: a `parking_left_m` and
  `parking_right_m` inside the paved width). Traffic lanes and markings keep to the
  carriageway; bays fill with parked cars by the hour like lots.
- **Not in this change:** paid parking, parallel-parking AI.

## Impact
- Affected specs: `parking` (ADDED: Street-Side Parking; ADDED: Lot Layout Follows The Lot).
- Affected code: `tools/osm_import/parking.py`, `graph.py` (parking lane widths),
  `game/world/dressing/parking_lot_builder.gd`, `parked_cars.gd`, `lane_graph.gd` and
  `marking_builder.gd` (carriageway, as for shoulders); schema; pack re-exported.
- Depends on the carriageway helpers from `add-road-shoulders` (merged).
