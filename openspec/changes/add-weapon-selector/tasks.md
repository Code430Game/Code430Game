## 1. Wheel
- [ ] 1.1 Icons: seven original SVGs (fists, paint brush, knife, sabre, paintball gun, pistol, blaster) plus a generic icon for each mechanic and a missing-icon tile; optional `icon` in `weapons.schema.v0.json`; `WeaponSet.icon_name` lookup order; tests on the lookup and the fallbacks
- [ ] 1.2 `WeaponSet.pick` and `available`; LB / Tab tap steps and hold opens; keys 1 to 9 pick; `controls.json`, `project.godot`, regenerated `docs/controls.md`; tests on tap versus hold, picking and skipping in every tone
- [ ] 1.3 `weapon_wheel.gd` with a `WheelPage` interface and one `WeaponPage` (page stepping on RB / Q, hidden with one page; a test with a second fake page): segments from `WeaponSet`, stick and mouse selection with a deadzone, release takes, B / Esc cancels, camera look paused, fire ignored while open, no change to time, outer ring past `max_segments`, rebuild on a tone change; `hud.accent` per mode through `ContentMode`; tests on the direction-to-segment maths, segment counts per tone, cancel and the rebuild (no orphan nodes)
- [ ] 1.4 Idle tile with the slot in hand and a flash on a tap-step; tests on the flash and the tone rebuild
- [ ] 1.5 Mac screenshots of the open wheel in clean, gritty and dystopia, and of the idle tile

## 2. Verification
- [ ] 2.1 Deck benchmark on the usual route: no change
- [ ] 2.2 Human opens the wheel on the Deck in each tone and says whether the icons read at a glance and the stick picks feel right
