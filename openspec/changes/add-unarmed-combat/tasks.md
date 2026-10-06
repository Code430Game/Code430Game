## 1. Moves
- [x] 1.1 Slot 0 punch (alternating) and held-then-released kick in `Shooter`; `fist` impact kind; reach and rate in `combat_config.json`; tests on timing and the hit path
  - A tap of fire throws the punch on release (a held fire can still become a kick); past `kick_hold_s` the leg draws up as the cue. Fists are not a weapon definition: `WeaponSet.current()` stays `{}` for slot 0 so the HUD and held model are unchanged, and `Shooter.fist_weapon(move)` builds the dictionary the hit path takes. Reach reuses the melee sphere sweep. Tunables under `fists` in `combat_config.json`; `fist` added to the weapons schema's impact enum and a `thud` voice to `CombatEffects`.
- [x] 1.2 Poses: jab on each arm through `bone_override`, kick through a new leg override in `CharacterRig`; tests on the pose maths like `test_held_weapon.gd`
  - `HeldWeapon.jab_pose(side, t)` poses both arms (the other in guard); `kick_pose(t)` chambers, snaps out at hip height and returns. `CharacterRig` gained `leg_override` and `leg_weight`, blended after the arm override, so a kick and an arm pose can run together. The kicking leg is `thigh_r`/`shin_r` as proposed, which is the body's left (the rig's "_l" side is the body's right).
- [x] 1.3 Reactions by tone (knock-down on the third punch or a kick; a shove in clean) and wanted reports; tests in every tone
  - The knock-down reads `ContentMode.flag("violence")` rather than a mode id. Any hit that does not floor someone is `PedestrianManager.shove()`: they face the hitter and rock back for `stumble_s`, then run off (the first two punches in gritty too). Reports go through the existing `hit_person` signal, so the testbed's `assault` / `assault_down` mapping covers fists unchanged. Officers punch (`officer_punch_*` in `police_config.json`) only when the tone resolves no officer weapon; the first-party tones all give one, so it is tested with an empty officer weapon.
- [x] 1.4 Mac screenshots: a punch and a kick mid-move
  - New testbed flag `--fists=punch|kick` pins the move mid-way. Taken with `--benchmark=5 --preset=deck --traffic=0 --peds=0 --mute --camera=645.5,75.0,1006.5,642,74.5,1005`.

## 2. Verification
- [ ] 2.1 Deck benchmark: no change on the usual route
- [ ] 2.2 Human tries fists and kicks in clean and gritty on the Deck
