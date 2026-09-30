# Graphics presets

Two presets exist from day one, defined as data in `game/core/settings/presets.json`. Every rendering feature must appear in both, and the test `test_every_feature_declared_in_both_presets` enforces it. The `deck` preset is selected automatically on Steam Deck hardware; the player can override it and the choice persists in `user://settings.cfg`.

| Feature | `deck` | `high` | Where it is applied |
|---|---|---|---|
| 3D scaling | FSR 2 at 0.77 (about 986×616 internal) | bilinear at 1.0 | viewport |
| MSAA 3D | off | 2x | viewport |
| Screen-space AA | FXAA | off | viewport |
| SDFGI | off (required by AGENTS.md) | on | Environment via `PresetEnvironment` |
| Screen-space reflections | off | on | Environment |
| SSAO | off | on | Environment |
| SSIL | off | off | Environment |
| Volumetric fog | off | on | Environment |
| Glow | on | on | Environment |
| Directional shadow atlas | 2048 | 4096 | RenderingServer |
| Positional shadow atlas | 2048 | 4096 | viewport |
| Soft shadow quality | low | high | RenderingServer |
| FPS cap | none | none | Engine |

## Adding a feature
1. Add the key to both presets in `presets.json`.
2. Apply it in `Settings.apply_preset` (viewport or server level) or `Settings.apply_to_environment` (Environment level).
3. Say in the OpenSpec proposal how it behaves in each preset and whether it changes Deck frame time.

## Deck detection
`DeckDetector.is_steam_deck` returns true on Linux when any of these holds: the `SteamDeck` environment variable is set, the DMI product name starts with `Jupiter` or `Galileo`, or the screen is exactly 1280×800. A false positive only costs a lower preset, and the override fixes it.
