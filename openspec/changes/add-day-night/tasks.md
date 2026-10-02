## 1. Clock and sky
- [x] 1.1 `day_night.gd`: clock, sun direction and energy, sky and ambient blends, config, flags, HUD clock; tests on sun elevation and energy by hour
- [x] 1.2 Night factor drives car light, signal head and window emission; player headlights as spot lights after dusk; presets declare behaviour
- [x] 1.3 Co-op: host clock replicated with the signal clock

## 2. Verification
- [x] 2.1 Deck (2026-10-01, idle, 23:00, 150 cars, 120 people, headlights on): GPU 7.16 ms against 6.45 ms by day, render CPU 0.85 ms, physics 5.72 ms, p99 11.1 ms; Mac screenshots at 12:07, 18:25 and 23:07 checked
- [x] 2.2 Human drove through day and night on the Deck (2026-10-02): "the night and day seem to work"
