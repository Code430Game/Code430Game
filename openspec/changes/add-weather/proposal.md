# Change: Clouds and weather

**Status: proposed 2026-10-02 (human: "we should also add clouds, and I guess weather").**

## Why
The sky is a flat procedural gradient under one sun, every day of the year. Clouds are the
cheapest way to give the city a second mood axis on top of the clock, and weather turns the
same streets into different driving: wet roads glisten under the headlights, snow mutes the
block colours, fog closes the Queensway in. `add-day-night` already blends the sky, ambient
and fog by the hour and broadcasts the clock to co-op peers; weather rides on the same hooks.

## What Changes
- **Clouds.** A cloud layer in the sky shader: a tiling procedural noise texture scrolled by
  wind, with `coverage` 0 to 1 and a density curve so the sun dims through overcast. `deck`:
  one layer, no shadow. `high`: a second slower high layer and soft cloud shadows from a
  projected noise texture on the sun's shadow (a light projector texture, no volumetrics).
  `presets.json` gains `cloud_layers` and `cloud_shadows`.
- **Weather as data.** `game/world/sky/weather.v0.json`: states `clear`, `overcast`, `rain`,
  `snow`, `fog`, each with coverage, precipitation rate, fog density, wind speed and
  direction range, temperature, sky tint, transition seconds, and a `next` row of weighted
  transitions (a Markov table). A `WeatherController` node (`world/sky/weather.gd`) picks the
  next state from the table with a seeded RNG when the current one's duration lapses, and
  blends every value over the transition time; the clock gates snow to cold hours only until
  seasons exist. Testbed flags `--weather=<state>` (hold that state) and `--weather-seed=`.
- **Precipitation.** One `GPUParticles3D` box following the camera: rain streaks stretched
  along fall velocity plus wind, or snowflakes drifting; counts and box size per preset.
  Nothing lands, nothing splashes.
- **Wet and snowy surfaces.** A `wetness` value rises in rain and dries over time; the road,
  junction and marking materials read it through a shader uniform that lowers roughness,
  darkens albedo and raises specular so headlights and the sky reflect in the surface; `ssr`
  stays a preset decision. A `snow` value rises in snow and melts over time; terrain, roofs
  and sidewalks blend toward a snow colour above it. No accumulation meshes, no tyre tracks.
- **Fog.** The fog state drives the existing distance fog density and colour in `DayNight`;
  `volumetric_fog` stays off on `deck`, on `high` the volumetric density follows too.
- **Sound.** Rain level on the ambience synth (filtered noise bed scaled by precipitation),
  under the existing Ambience bus.
- **Gameplay hooks.** `traffic_config.json` gains `weather_speed_factor` per state (rain 0.85,
  snow 0.7, fog 0.8) applied to the lane limit in `traffic_manager.gd`; the player's car gets
  a `grip_factor` per state applied to `wheel_friction_slip` (rain 0.8, snow 0.55), identical
  on both presets; the headlight `AUTO` mode treats heavy rain, snow and fog as dusk.
- **Not in this change:** seasons and real Ottawa climate tables, wipers, umbrellas, puddles
  and splashes, snow accumulation or ploughing, thunder and lightning, wind on trees
  (`add-vegetation` owns sway), weather on the overview map.

## Co-op authority
The host owns the weather: its seed, current state, next state and transition progress travel
with the clock in `WorldSync._signal_time`, so a guest blends to the host's sky within one sync
interval and never rolls its own table. Wetness and snow values are derived locally from the
replicated state so they match without extra traffic.

## Tone
Weather is not content and carries no descriptors. The only mode hook is a `weather_bias`
flag in the mode definition that `dystopia` may set to weight the table toward rain and fog;
`ContentMode.flag("weather_bias")` is read in one place, the table pick.

## Impact
- Affected specs: `weather` (new), `world-time` (new requirement: sky follows weather),
  `traffic` (new requirement: weather slows traffic).
- Affected code: `game/world/sky/weather.gd` (new), `weather.v0.json` (new), `sky.gdshader`
  (new, replaces the `ProceduralSkyMaterial` in `play_testbed.tscn` with a `ShaderMaterial`
  driven by `DayNight`), `day_night.gd` (fog hook, sky uniforms), `precipitation.gd` (new),
  road and marking materials in `map_pack.gd` and `marking_builder.gd` (wetness uniform),
  `terrain`, `building_builder.gd` and `sidewalk_builder.gd` materials (snow uniform),
  `ambience_audio.gd` (rain bed), `traffic_manager.gd` and `traffic_config.json`,
  `placeholder_car.gd` (grip), `play_testbed.gd` (flags, headlight auto),
  `world_sync.gd` (state in the clock sync), `presets.json` and `docs/graphics-presets.md`,
  `content_mode.gd` modes (optional flag), tests.
- Performance: the sky shader gains one noise sample per pixel on `deck` (two plus a shadow
  projector on `high`); one particle system; material uniforms are free. Budgets in
  `design.md`. Deck measured in rain at night, the worst case.
