# Change: One height for side-by-side bridge carriageways

**Status: proposed 2026-10-06 from the backlog (issue #45 follow-up: the Mackenzie King Bridge at x 517, z -523).**

## Why
Where two carriageways of one bridge touch, they can sit at different heights: on the
Mackenzie King Bridge the 2-lane way is about 0.48 m above the 3-lane one, so the deck's side
face shows as a low strip between them. #45 removed the parapets from that gap, but the step
remains. The 417's carriageways have smaller steps of the same kind (`add-road-shoulders`
dropped 62 shoulders where heights differed).

## What Changes
- The elevation stage groups bridge carriageways whose ribbons touch or overlap (gap under
  1 m, same structure in `bridges.py`'s grouping) and gives each group one height profile:
  the mean of the members at each station along the span, blended into each member's own
  approach over `blend_m`.
- The same rule applies on the ground to carriageways of one motorway whose ribbons overlap,
  where the median is paved.
- Afterwards, re-run shoulder trimming: shoulders dropped only because of the step come back.
- **Not in this change:** decks of different bridges crossing over each other.

## Impact
- Affected specs: `road-network` (ADDED: Shared Height For Touching Carriageways).
- Affected code: `tools/osm_import/elevation.py` (a pass after `apply_elevation`),
  `bridges.py` (grouping reused), `shoulders.py` (order); golden fixture; pack re-exported.
- Overlaps: `add-road-shoulders` 1.4 (infill between carriageways) depends on this; land this
  first.
