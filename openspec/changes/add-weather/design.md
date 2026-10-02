# Design: weather

## States and the table
`weather.v0.json`:
```
{ "states": {
    "clear":    {"coverage": 0.15, "precip": 0.0, "fog": 0.0,  "wind": [1, 4],  "temp_c": [8, 26],  "duration_s": [900, 2400], "transition_s": 120, "tint": [1,1,1],
                 "next": {"clear": 0.6, "overcast": 0.4}},
    "overcast": {"coverage": 0.85, "precip": 0.0, "fog": 0.05, "wind": [2, 7],  "temp_c": [2, 18],  "duration_s": [600, 1800], "transition_s": 180, "tint": [0.9,0.92,0.96],
                 "next": {"clear": 0.35, "rain": 0.35, "snow": 0.15, "fog": 0.15}},
    "rain":     {"coverage": 0.95, "precip": 1.0, "fog": 0.12, "wind": [3, 9],  "temp_c": [3, 20],  "duration_s": [400, 1200], "transition_s": 90,  "tint": [0.8,0.84,0.9],
                 "next": {"overcast": 0.7, "rain": 0.2, "fog": 0.1}},
    "snow":     {"coverage": 0.95, "precip": 1.0, "fog": 0.2,  "wind": [1, 6],  "temp_c": [-15, 0], "duration_s": [600, 1800], "transition_s": 120, "tint": [0.85,0.87,0.92],
                 "next": {"overcast": 0.6, "snow": 0.3, "clear": 0.1}},
    "fog":      {"coverage": 0.5,  "precip": 0.0, "fog": 0.6,  "wind": [0, 2],  "temp_c": [0, 12],  "duration_s": [300, 900],  "transition_s": 150, "tint": [0.88,0.9,0.92],
                 "next": {"overcast": 0.5, "clear": 0.5}}
  },
  "start": "clear", "wetness_rise_s": 60, "wetness_dry_s": 900, "snow_rise_s": 300, "snow_melt_s": 1800 }
```
- The controller holds `state`, `next_state`, `t` (0..1 through the transition), `seed` and
  the RNG. Every blended value is `lerp(state.value, next.value, smoothstep(t))`; `precip`
  is the only one that also gates the particle emitter.
- `snow` is only chosen when the clock says night or early morning until seasons exist, so a
  24-minute day does not flip from heat to snow at noon; the `temp_c` ranges are carried for
  the HUD and for the later season table.
- `--weather=rain` pins the state (no table), `--weather-seed=N` seeds the table; the host's
  seed is otherwise random per session and sent to guests.

## Sky shader
- `sky.gdshader` reproduces the day-night gradient (top, horizon, sun disc, moon) from the
  uniforms `DayNight` already computes, plus `cloud_coverage`, `cloud_offset` (wind times
  time), `cloud_tint`, `night`. Clouds are two octaves of a 512 px tiling value-noise texture
  generated once at boot (seeded, byte-identical), thresholded by coverage with a soft edge
  and lit by the sun direction so their bases darken toward the horizon.
- `deck`: `cloud_layers: 1`, `cloud_shadows: false`. `high`: `cloud_layers: 2` (the second at
  half scale, quarter speed) and `cloud_shadows: true`, a `Texture2D` projector on the sun
  using the same noise so shadows match the sky roughly; no volumetrics anywhere.

## Precipitation
- One `GPUParticles3D` with a 24 m box centred 4 m ahead of the camera, emitting downward with
  the wind vector; rain uses a stretched quad with `billboard: particles`, snow a soft dot
  with slow lateral drift. `deck`: 1500 rain / 600 snow particles; `high`: 6000 / 2500.
  Lifetime trimmed so particles never pass below the camera's ground height.
- Emission amount is `precip` times the preset cap, so a transition fades the rain in.

## Surfaces
- Road, junction and marking materials gain a `wetness` uniform: roughness
  `lerp(0.85, 0.25, wetness)`, albedo darkened by up to 35 %, specular raised to 0.6. At
  night the headlight spot lights already exist, so wet asphalt reflects them with no new
  lights. `high` adds nothing extra: `ssr` is already on there.
- Terrain, roofs, sidewalks and bus shelters gain a `snow` uniform blending toward a snow
  albedo; roads do not whiten (ploughed) but darken slightly as wet.
- Uniforms are set once per frame on the shared materials by the controller; chunks need no
  per-instance data.

## Replication
`_signal_time(t, hour)` becomes `_signal_time(t, hour, weather: PackedFloat32Array)` with
`[state_index, next_index, t, seed, elapsed]`; guests apply the state and keep blending
locally. Five floats every 5 s; nothing else.

## Budgets
| | deck | high |
|---|---|---|
| cloud layers | 1 | 2 |
| cloud shadows | off | projector |
| rain / snow particles | 1500 / 600 | 6000 / 2500 |
| fog | distance fog only | distance + volumetric density |
| expected cost | sky +0.2 ms, particles +0.3 ms | sky +0.5 ms, particles +0.6 ms, projector +0.3 ms |

## Decisions for the human
- Snow at all before seasons exist (gated to night hours), or clear/overcast/rain/fog only
  until a season table lands?
- Headlight auto mode switching on in weather: fine, or keep auto strictly dusk to dawn?
- Default grip in snow 0.55 is a noticeable slide; say if you want it tamer for the Deck.
