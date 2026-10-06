# Change: Garage polish

**Status: proposed 2026-10-06 from the backlog (add-underground-parking follow-ups, 2026-10-05).**

## Why
Two loose ends from underground parking:
- inside a garage, the minimap still shows the street above;
- beside some ramps, the 4 m terrain cut leaves black triangles past the coping (the museum
  ramp).

## What Changes
- **Minimap inside.** While the player is on a garage level, the minimap draws that garage's
  floor: outline, stalls, ramps and the player's position, from `GarageBuilder.Garage` data.
  It switches back at the top of the ramp.
- **Ramp cut.** The terrain hole is cut to the ramp strip plus the coping per cell, not a
  4 m square, so no gap shows beside the ramp walls.
- **Not in this change:** multi-level garages, garage doors that open.

## Impact
- Affected specs: `parking` (ADDED: Garage Minimap And Clean Ramp Cuts).
- Affected code: `game/ui/map/minimap.gd`, `game/world/dressing/garage_builder.gd`
  (`holes_by_chunk`), terrain hole handling in `map_pack.gd`; tests.
- No dependency on other open changes.
