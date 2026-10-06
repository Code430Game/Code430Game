# Change: Road shoulders and filled deck gaps

**Status: proposed 2026-10-05 (human, looking at the 417 over Metcalfe: "what look like walls for the bridge. I wonder if they are elsewhere too if a simple solution is adding some road spacing outside the lane and also just filling those half hexagon walls with a cement floor. Also the highway could use the same spacing on the outside of the lanes.")**

## Why
The 417's carriageways are drawn exactly as wide as their lanes. Where one carriageway runs
beside another, or splits from a ramp, the parapets (`add-bridge-structures`) make
three-to-six-sided wall enclosures with nothing inside: grass or the street shows through
from below, and from the street the walls look like they hang in the air. Real motorways
have a paved shoulder outside the outer lanes, and between close carriageways and ramps
there is concrete, not a hole.

## What Changes
- **Shoulders.** Motorway, trunk and their links get a paved shoulder outside the outer
  lanes, wider on the right (`shoulder_right_m` 2.5, `shoulder_left_m` 1.0). The edge line
  stays at the lane edge, so the shoulder reads as shoulder. Bridge decks get the same
  shoulder, and parapets move out to its edge. Other classes are unchanged; they have
  sidewalks and curbs.
- **Filled gaps.** On a bridge, the space enclosed between parapets of carriageways of the
  same structure (side-by-side decks, a ramp splitting or merging) gets a concrete floor at
  deck height when it is narrower than `infill_max_m` (8 m). The parapets on the facing
  edges are dropped, leaving one outer wall. On the ground, the same gaps between motorway
  carriageways and their ramps become a paved gore area instead of grass.
- **Where it shows.** Every 417 overpass in the pack: Metcalfe, Elgin, O'Connor, Kent, Bank,
  and the ramps by the start.
- **Not in this change:** median barriers on the ground, rumble strips, emergency lay-bys.

## Impact
- Affected specs: `road-network` (ADDED: Road Shoulders And Deck Infill).
- Affected code: `tools/osm_import/` (shoulder widths per class in `road_classes.json`,
  ribbon widths, `barriers.py` parapet placement, `bridges.py` gap infill), the road and
  bridge mesh builders in `game/world/roads/`, terrain carving under the wider ribbons;
  tests; Ottawa pack re-exported.
- Before and after screenshots at the 417 over Metcalfe and Elgin. Deck benchmark (a few
  more triangles per chunk).
