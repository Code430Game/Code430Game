## 1. Wanted level
- [x] 1.1 `wanted.gd`: crimes, witnesses, stars, search radius, losing them out of sight; `police_config.json`; hooks from weapons, car hits and car taking; HUD stars; tests

## 2. Police
- [x] 2.1 Police vehicle: catalogue entry, livery, flashing light bar, siren voice; tests
- [x] 2.2 `police_manager.gd` and `police_car.gd`: spawn out of view per star, chase along the road graph, ram and box, despawn when clear; tests in a lab scene
- [x] 2.3 Officers: get out near a player on foot, run at them, tone weapon (net gun sticks, pistol or blaster damage); tests per tone
- [x] 2.4 Busted and wasted: player health in lethal modes, the busted check, fade and respawn, wanted cleared; tests
- [x] 2.5 Mac screenshots: a 2-star chase, a net gun in clean, busted
  - 2026-10-05: chase screenshots from the start position shared; the chase is easier to judge from `--police-log` (each second: stars, cars, officers, distance and speed per car), which showed two cars closing from 140 m to 25 m, an officer getting out, and a bust about 14 s in. `--wanted=N` starts a chase. First-pass limits: officers walk straight at the player and follow their height (they float up to a deck), and police cars ignore one-way rules

## 3. Verification
- [ ] 3.1 Deck benchmark during a 3-star chase against main
- [ ] 3.2 Human tries a chase in clean and gritty on the Deck (feedback to the backlog; not a merge gate)
