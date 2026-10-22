## 0. Confirm
- [ ] 0.1 The human confirms the open choices in the proposal (dystopia sparks, explosions, garage repair free or only when not wanted)

## 1. Car damage
- [ ] 1.1 `VehicleDamage`: health from crashes (closing speed above a threshold) and weapon hits (`vehicle_damage` per weapon), stages (scuffed, dented, smoking, wrecked), tunables in `vehicle_damage.json`; tests on the maths (a gentle bump does nothing, a hard crash dents, enough hits wreck)
- [ ] 1.2 Looks: scrape marks, dents (a per-car mesh copy only once dented, vertices pushed in around the hit, capped), cracked windscreen, a light out on a front or rear hit, engine smoke; smoking halves top speed and pull; tests (undamaged cars still share the mesh, the copy cap)
- [ ] 1.3 Wrecks by `outcomes.vehicle`: `conk_out` (clean: stalls, smoke puffs, mended by reset) and `burn` (smoke, then fire, then a blackened shell); the player gets out of a wreck; mode schema and the three modes; tests in every tone
- [ ] 1.4 Repair: reset keeps damage (except a clean wreck); a garage mends it; tests
- [ ] 1.5 Traffic and parked cars take the same damage; a wrecked traffic driver gets out and runs; wrecks despawn as traffic does; `property_damage` crime when the police see it; tests

## 2. Buildings
- [ ] 2.1 Glass panes break on a shot or a hard hit (shards, sound, a broken-pane mark); crash scrape and dent marks on walls; scorch marks by a burning wreck; all through the mark cap; tests (a hit on glass breaks a pane, a hit on brick doesn't)

## 3. Co-op and the log
- [ ] 3.1 The driver's car damage (stage, dent points) in the vehicle state; the host's traffic and parked car damage; a guest sees the same dents and the same wreck; tests
- [ ] 3.2 Play log events (`vehicle_damaged`, `vehicle_wrecked`, `vehicle_repaired`, `pane_broken`) if `add-play-log` is built

## 4. Check
- [ ] 4.1 Mac screenshots: each stage, a wreck in each tone, a broken pane, a crash mark; `docs/` updated
- [ ] 4.2 Deck: package, deploy, benchmark a pile-up (five wrecks, two burning) against main
- [ ] 4.3 **Stop: the human crashes and shoots cars and windows on the Deck and says how it looks**
