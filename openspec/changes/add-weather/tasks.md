## 1. Sky and data
- [ ] 1.1 `weather.v0.json` and `WeatherController`: states, seeded table, transitions, pinned `--weather=` and `--weather-seed=`, night gate for snow; tests on determinism (same seed, same sequence) and blend values
- [ ] 1.2 `sky.gdshader` replacing the procedural sky with the same day-night look plus one cloud layer; `DayNight` feeds the uniforms; `presets.json` gains `cloud_layers` and `cloud_shadows`, `high` adds the second layer and the shadow projector; preset doc updated; preset test passes

## 2. Precipitation and surfaces
- [ ] 2.1 `precipitation.gd` camera-following particle box, rain and snow, counts per preset
- [ ] 2.2 Wetness and snow uniforms on road, marking, terrain, roof and sidewalk materials; rise and dry times from data; fog state hooked to the distance fog (and volumetric density on `high`); rain bed in `ambience_audio.gd`
- [ ] 2.3 Mac screenshots: overcast noon, rain at night with headlights on wet Bank Street, snow at dawn, fog on the Queensway

## 3. Gameplay and co-op
- [ ] 3.1 Traffic speed factor per state; player grip factor; headlight auto in heavy weather; tests on the factors
- [ ] 3.2 Weather state in the clock sync; guest blends to the host's state; test with a mirrored controller

## 4. Verification
- [ ] 4.1 Deck benchmark in rain at 23:00 on the usual route; sky and particle cost stated against the clear-day run; no regression past budget
- [ ] 4.2 **Stop: human drives through a rain storm and a snowfall on the Deck**
