# Change: Police helicopter

**Status: proposed 2026-10-05 (human: "Are there helipads? XD Is that too crazy?"). There is one helipad in the Ottawa bbox (OSM way 121189893); `add-emergency-services` imports it.**

## Why
Three stars should feel different from two. A helicopter overhead that keeps you in sight is
the classic top-level pressure, and it gives the helipad in the data a job.

## What Changes
- At 3 stars, one police helicopter lifts off from the nearest helipad (or appears high at the
  edge of the district when there is none) and flies to the player. It circles at about 60 m
  and counts as police sight, so the stars don't drop while it watches.
- At night a searchlight cone follows the player. Under a bridge, in a garage or a tunnel, or
  under thick tree cover, it loses sight, and the losing timer runs again.
- Low-poly body built in code, spinning rotors, a synthesised rotor thump.
- It returns to the helipad and despawns when the level drops below 3.
- **Not in this change:** shooting from the helicopter, the player flying it, news
  helicopters.

## Impact
- Affected specs: `police` (ADDED: Helicopter At Three Stars).
- Affected code: `game/actors/police/helicopter.gd` (new), `police_manager.gd`, `Synth`,
  `wanted.gd` (sight checks with cover); tests.
- Performance: one body and one spot light; Deck benchmark during a 3-star chase at night.
