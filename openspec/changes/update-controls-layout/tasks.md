## 1. Layout
- [x] 1.1 Input map: horn (L3 drive), look behind (R3 tap), reset on R3 hold with HUD ring, headlights to D-pad right, `radio_cycle` D-left reserved, combat actions reserved (LT aim, RT fire, LB weapon, B reload); `test_input_map.gd` per-context conflict test covers both contexts
- [x] 1.2 `placeholder_car.gd` and `chase_camera.gd`: hold-to-reset, look behind; `vehicle_audio.gd` horn voice via `Synth`; tests
- [x] 1.3 Update the binding paragraphs in `add-weapons-and-combat` and `add-car-radio` to this layout (the radio shipped on D-pad left already, archived; nothing to change)

## 2. Remapping
- [ ] 2.1 Settings overrides for bindings, applied at boot before any scene reads the map; tests
- [ ] 2.2 Pause menu controls page: list, press-to-rebind, conflict refusal, reset to default; works with a controller alone on the Deck

- [ ] 2.3 Tabbed start and pause menus (Controls, Options, Settings, first tab for the existing items), LB/RB and Q/E cycle tabs; the home screen's controls list moves to the Controls tab and shows the current device's layout (controller or keyboard and mouse); nothing runs off screen at 1280×800; tests and a Deck screenshot

## 3. Doc
- [ ] 3.1 `tools/controls_doc.py` generates `docs/controls.md`; CI stale check; doc regenerated

## 4. Verification
- [ ] 4.1 Deck benchmark unchanged (no rendering change); on-foot and driving contexts checked with a controller alone
- [ ] 4.2 **Stop: human drives on the Deck: handbrake never resets, horn on L3, look behind on R3, hold R3 to reset**
