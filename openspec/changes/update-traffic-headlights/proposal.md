# Change: Other cars' headlights

**Status: built 2026-10-09 at the human's request ("we need to add other people's headlights too").**

## Why
At night only the player's car lights the road. Traffic shows glowing lamps but casts no light,
so streets stay dark around moving cars and they are hard to read.

## What Changes
- Every traffic car within `headlight_pool_m` (120 m) of a player lights a patch of road ahead
  of it after dusk: one MultiMesh of soft additive quads for the whole city, faded in with the
  day-night `night` value.
- The nearest `traffic_headlights` cars (preset: 6 on the Deck, 16 on high) also carry a real
  spot light without shadows, moved onto them each frame.
- Tunables in `traffic_config.json` defaults (`headlight_pool_m`, `headlight_pool_length_m`,
  `headlight_pool_width_m`, `headlight_energy`, `headlight_range_m`).

## Impact
- Affected specs: `traffic` (ADDED: Traffic Headlights At Night).
- Affected code: `game/world/traffic/traffic_manager.gd`, `headlight_pool.gdshader`,
  `game/core/settings/presets.json`, the testbed (night value); tests.
