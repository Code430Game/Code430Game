## 1. Data
- [x] 1.1 `weapons.schema.v0.json`, `weapons.v0.json` (melee and gun with clean, gritty and dystopia variants), `combat_config.json` (impact kinds: decal, sound, reaction; decal caps; flee time and earshot); `pack_tools` validates weapon files and refuses `lethal` variants keyed to a mode whose flag is off; tests

## 2. Game
- [x] 2.1 `WeaponSet`: loads definitions, picks the variant for the tone, swaps on a mode change; slot cycling on LB / Tab; tests for each mode
- [x] 2.2 `Shooter` on the player: aim (over-the-shoulder camera and reticle), hitscan, paintball projectiles, melee sweep, magazines and reload; HUD weapon and ammo; tests on rate, reload and the hit path
- [x] 2.3 Impacts: decal pool per preset, muzzle flash and bolt glow, synthesised voices; mode switch clears decals; tests on pool recycling
- [x] 2.4 Pedestrian reactions: lethal to `knock_down`, blood only with gore, paint tint and `FLEEING`, earshot flee; tests in every mode
- [x] 2.5 Mac screenshots: paintball gun in `clean`, pistol in `gritty`, blaster and sabre in `dystopia`
  - 2026-10-05: gun shots shared for clean (paint blobs, "Paintball gun 12 / 20") and dystopia (scorch marks, "Blaster 8 / 16"); `--weapon=1|2 --shoot=N` holds a weapon and fires for screenshots. Marks are flat blobs (paint, blood) or discs (holes, scorch), not textured decals. Punching and kicking are a follow-up (human: "that could be a different ticket"); empty hands stay in the cycle

## 3. Verification
- [x] 3.1 Deck benchmark: 30 s of firing on a busy street with the decal pool full; frame avg and p99 against main
  - 2026-10-05, idle Deck, deck preset: route avg 13.11 ms, p99 17.78. 30 s firing from the start in gritty (`--weapon=2 --shoot=120`, mark pool full) avg 12.47, p99 17.50; the same in clean with paintballs avg 12.47, p99 17.52. No cost from weapons
- [ ] 3.2 Human tries all three tones on the Deck (feedback goes to the backlog; not a merge gate)
