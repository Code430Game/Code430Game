## 1. Wheel
- [x] 1.1 Icons: seven original SVGs (fists, paint brush, knife, sabre, paintball gun, pistol, blaster) plus a generic icon for each mechanic and a missing-icon tile; optional `icon` in `weapons.schema.v0.json`; `WeaponSet.icon_name` lookup order; tests on the lookup and the fallbacks
- [x] 1.2 `WeaponSet.pick` and `available`; LB / Tab tap steps and hold opens; keys 1 to 9 pick; `controls.json`, `project.godot`, regenerated `docs/controls.md`; tests on tap versus hold, picking and skipping in every tone
- [x] 1.3 `weapon_wheel.gd` with a `WheelPage` interface and one `WeaponPage` (page stepping on RB / Q, hidden with one page; a test with a second fake page): segments from `WeaponSet`, stick and mouse selection with a deadzone, release takes, B / Esc cancels, camera look paused, fire ignored while open, no change to time, outer ring past `max_segments`, rebuild on a tone change; `hud.accent` per mode through `ContentMode`; tests on the direction-to-segment maths, segment counts per tone, cancel and the rebuild (no orphan nodes)
- [x] 1.4 Idle tile with the slot in hand and a flash on a tap-step; tests on the flash and the tone rebuild
- [x] 1.5 Mac screenshots of the open wheel in clean, gritty and dystopia, and of the idle tile

Notes (2026-10-06):
- Icons: eleven one-colour SVGs on a 64 grid in `game/ui/hud/icons/weapons/` (CC BY-SA 4.0 in each file's comment), imported at 2x with mipmaps and drawn with mipmapped filtering. Checked on a contact sheet at 128 and 40 px; the first fist merged into a block at 40 px, so the palm, fingers and thumb now have gaps. `WeaponSet.icon_names` gives the lookup order and `WeaponIcons` resolves it, PNG paths for packs included; the officers' net gun has no icon and falls to the generic projectile, which a test checks.
- Tap against hold lives in `Shooter.step_next` (like `step_fists`): a tap now steps on release rather than on press, up to 0.2 s later. A hold opens the wheel at `hold_s`; the release takes what is pointed at; after a cancel with LB still held, the release does not step.
- The stick lets go of a selection when it returns to the middle (the proposal's "released with the stick centred keeps the slot"); the mouse keeps its accumulated direction.
- B is also reload and Esc is also pause: the wheel's layer is added after the pause menu so it takes B / Esc first, and the Shooter ignores fire and reload for 150 ms after a close so the press that closed it does nothing else.
- `wheel_page` (RB / Q) is bound and marked reserved in `controls.json`: hidden from the controls list until a second page exists, but no other on-foot action may take RB or Q. Keys 1 to 9 are keyboard shortcuts (controllers use the wheel), listed as such in `test_input_map.gd`.
- Tone accents (`hud.accent` in the mode files, optional in `tone-mode.schema.v0.json`): clean #ff4fa3, gritty #d9a441, dystopia #3ff0ff.
- Placement: the HUD's weapon line is at the top right and the minimap at the bottom left, so the idle tile sits under the weapon line (design.md updated). The wheel got a soft dark disc behind it after the first screenshot, for bright skies.
- Tests: `test_weapon_wheel.gd`, 22 cases.
- Testbed: `--wheel=N` opens the wheel pointing at entry N (`-1` for none).

## 2. Verification
- [ ] 2.1 Deck benchmark on the usual route: no change
- [ ] 2.2 Human opens the wheel on the Deck in each tone and says whether the icons read at a glance and the stick picks feel right
