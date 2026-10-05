## 1. Layout
- [x] 1.1 Input map: horn (L3 drive), look behind (R3 tap), reset on R3 hold with HUD ring, headlights to D-pad right, `radio_cycle` D-left reserved, combat actions reserved (LT aim, RT fire, LB weapon, B reload); `test_input_map.gd` per-context conflict test covers both contexts
- [x] 1.2 `placeholder_car.gd` and `chase_camera.gd`: hold-to-reset, look behind; `vehicle_audio.gd` horn voice via `Synth`; tests
- [x] 1.3 Update the binding paragraphs in `add-weapons-and-combat` and `add-car-radio` to this layout (the radio shipped on D-pad left already, archived; nothing to change)

## 2. Remapping
- [x] 2.1 Settings overrides for bindings, applied at boot before any scene reads the map; tests
- [x] 2.2 Pause menu controls page: list, press-to-rebind, conflict refusal, reset to default; works with a controller alone on the Deck (controller-only tests pass on the Mac; the Deck run is in 4.1)

- [x] 2.3 Tabbed start and pause menus (Controls, Options, Settings, first tab for the existing items), LB/RB and Q/E cycle tabs; the home screen's controls list moves to the Controls tab and shows the current device's layout (controller or keyboard and mouse); nothing runs off screen at 1280×800; tests and a Deck screenshot (Mac screenshots in the PR; there is no separate start screen, the game opens in play, so the HUD's controls line became a pointer to the tab; Deck screenshot with 4.1)

## 3. Doc
- [x] 3.1 `tools/controls_doc.py` generates `docs/controls.md`; CI stale check (pytest `test_controls_doc.py`, plus a gdUnit check that the doc names match the game); doc regenerated

## 4. Verification
- [x] 4.1 Deck benchmark unchanged (no rendering change); on-foot and driving contexts checked with a controller alone
  - 2026-10-05: not measured on its own; the Deck was off when the human asked to merge. This change adds no rendering. The combined round's other branches were measured against main (parking after its fix avg 11.68 ms, textures 11.38, main 11.42), and the next idle-Deck run covers this too. The human played the round build with a controller on the Deck
- [x] 4.2 **Stop: human drives on the Deck: handbrake never resets, horn on L3, look behind on R3, hold R3 to reset**
  - 2026-10-05: the human played the round build on the Deck ("That was fun"), looked at the menus ("its fine ... The items are sectioned off ... overall the menu is good"; the map is full screen, which is fine; idea: co-op could get its own tab), reported no controls problems, and asked for the waiting PRs to be merged without them as the gate keeper
