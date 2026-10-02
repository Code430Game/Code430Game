# Change: Day and night

**Status: proposed 2026-10-01 (queue item: day and night; approved in conversation "do the day night and sounds").**

## Why
The city is lit by one fixed afternoon sun. A clock with a moving sun, dusk, night and dawn
gives the same streets a dozen moods for free, and the emissive parts already in place (car
lights, signal heads) start paying off after dark.

## What Changes
- **DayNight** node: time of day in hours, advancing at a configurable day length (default
  24 real minutes per day). Sun direction and energy follow the hour; colour warms at the
  horizon; below the horizon a faint moon light takes over. Sky top and horizon colours,
  ambient energy and fog blend between day, dusk and night sets. Tunables in
  `world/sky/day_night.json`; flags `--time=HH` and `--day-minutes=N`; HUD shows the clock.
- **Lights at night:** car head and tail lights, signal heads and building windows glow after
  dusk through emission scaled by a night factor; the player's car gets two real spot
  headlights when it is dark. Both presets declare it: `deck` uses emissive glow and the
  player's headlights only; `high` adds headlight shadows.
- **Co-op:** the host's clock is sent with the signal clock so everyone sees the same sky.
- **Not in this change:** street lamps as real lights, weather, interiors, a visible moon.

## Impact
- Affected specs: `world-time` (new).
- Affected code: `game/world/sky/day_night.gd` (new), `play_testbed.gd`, `car_mesh.gd`
  (night emission), `signal_heads.gd`, `building_builder.gd` (window glow), `world_sync.gd`,
  `presets.json`, tests.
- Performance: two spot lights at night on the player car; emission is free. Deck measured
  at night.
