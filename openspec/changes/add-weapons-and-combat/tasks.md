## 1. Data
- [ ] 1.1 `weapons.schema.v0.json`, the first-party `weapons.v0.json` (five weapons, clean variants), `combat_config.json` (impact kinds, decal caps, flee and down times); `pack_tools` validates weapon files and refuses `lethal` variants keyed to a mode whose flag is off; tests

## 2. Game
- [ ] 2.1 Input actions (`aim`, `fire`, `reload`, `weapon_next`, `weapon_prev`, `weapon_1..5`) and the input-map test; `WeaponSet` loads definitions, picks variants, handles mode changes
- [ ] 2.2 `Shooter` on the player: aim camera and reticle, hitscan, melee sweep, projectile pool, reload and magazines, debug refill; HUD slot and ammo; tests on spread, rate and reload
- [ ] 2.3 Impacts: decal pool per preset, muzzle flash, synthesised shot and pop voices; mode switch clears decals; tests on pool recycling
- [ ] 2.4 Pedestrian reactions: `FLEEING`, paint tint, lethal to `DOWN` with blood decal only when gore is allowed, earshot flee; traffic damage tint, disable threshold, tyre shot; tests in `test_pedestrians.gd` and `test_traffic.gd` for every mode
- [ ] 2.5 Player health, down and respawn; non-lethal paint on the character; HUD
- [ ] 2.6 Co-op: `report_shot`, `shot_fired`, player damage RPCs, state and tint in snapshots; `test_coop.gd` covers a guest shooting a host pedestrian
- [ ] 2.7 Mac screenshots: paint marker on Bank Street in `clean`, pistol in `gritty` with a fleeing crowd

## 3. Verification
- [ ] 3.1 Deck benchmark: a 30 s firefight on Bank Street with the decal pool full; frame avg, p99 and physics against the bus round baseline (avg 9.9 ms, p99 13.3)
- [ ] 3.2 **Stop: human shoots paintballs in clean and switches to gritty on the Deck**
