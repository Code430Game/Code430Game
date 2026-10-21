## 1. Data
- [x] 1.1 `weapons.schema.v0.json`, `weapons.v0.json` (melee and gun with clean, gritty and dystopia variants), `combat_config.json` (impact kinds: decal, sound, reaction; decal caps; flee time and earshot); `pack_tools` validates weapon files and refuses `lethal` variants keyed to a mode whose flag is off; tests

## 2. Game
- [x] 2.1 `WeaponSet`: loads definitions, picks the variant for the tone, swaps on a mode change; slot cycling on LB / Tab; tests for each mode
- [x] 2.2 `Shooter` on the player: aim (over-the-shoulder camera and reticle), hitscan, paintball projectiles, melee sweep, magazines and reload; HUD weapon and ammo; tests on rate, reload and the hit path
- [x] 2.3 Impacts: decal pool per preset, muzzle flash and bolt glow, synthesised voices; mode switch clears decals; tests on pool recycling
- [x] 2.4 Pedestrian reactions: lethal to `knock_down`, blood only with gore, paint tint and `FLEEING`, earshot flee; tests in every mode
- [x] 2.5 Mac screenshots: paintball gun in `clean`, pistol in `gritty`, blaster and sabre in `dystopia`
  - 2026-10-05: gun shots shared for clean (paint blobs, "Paintball gun 12 / 20") and dystopia (scorch marks, "Blaster 8 / 16"); `--weapon=1|2 --shoot=N` holds a weapon and fires for screenshots. Marks are flat blobs (paint, blood) or discs (holes, scorch), not textured decals. Punching and kicking are a follow-up (human: "that could be a different ticket"); empty hands stay in the cycle

- [x] 2.6 From the human's first try on the Deck ("I tried to stab and there was no real motion, I don't feel there was a weapon"): the player holds the current weapon (a low-poly knife, pistol, sabre, blaster, brush or paintball gun, per tone) in the right hand; a melee swing plays an arm swing with a short trail, and aiming raises the gun arm. Officers hold their tone weapon too. Tests

  - 2026-10-05: `HeldWeapon` (actors/combat): seven low-poly models chosen by a new variant field `model` (knife, sabre with a glowing blade, brush, pistol, blaster, paintball gun with its hopper, and the officers' net gun) on the weapon forearm. Poses blend over the walk cycle through a new `CharacterRig.bone_override`: held forward at the waist, raised along the line of sight while aiming, a slash from the right across to the left with a fading trail, and a kick up per shot. Shots and flashes start at the barrel's end. Officers hold their tone weapon and raise it when in range. Found on the way: officers and paramedics faced away from their target (an extra half turn); fixed. The start position moved to the outer lane with the player on the shoulder, because the road-shoulders change had put them on top of the median barrier

## 3. Verification
- [x] 3.1 Deck benchmark: 30 s of firing on a busy street with the decal pool full; frame avg and p99 against main
  - 2026-10-05, idle Deck, deck preset: route avg 13.11 ms, p99 17.78. 30 s firing from the start in gritty (`--weapon=2 --shoot=120`, mark pool full) avg 12.47, p99 17.50; the same in clean with paintballs avg 12.47, p99 17.52. No cost from weapons
- [x] 3.2 Human tries all three tones on the Deck (feedback goes to the backlog; not a merge gate)
  - 2026-10-21 Deck: the human: "All weapons work".
