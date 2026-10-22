## 0. Confirm
- [x] 0.1 The human confirms the open choices in the proposal (dystopia sparks, explosions, garage repair free or only when not wanted)
  - 2026-10-22: explosions yes ("Oh. Explode sounds fun!"); dystopia sparks "Maybe a little smoke too? Like a white smoke with sparks."; garage repair "when not wanted. Or not seen?": not seen (Claude's pick, so losing the police then ducking in works).

## 1. Car damage
- [x] 1.1 `VehicleDamage`: health from crashes (closing speed above a threshold) and weapon hits (`vehicle_damage` per weapon), stages (scuffed, dented, smoking, wrecked), tunables in `vehicle_damage.json`; tests on the maths (a gentle bump does nothing, a hard crash dents, enough hits wreck)
  - 2026-10-22: `VehicleDamage` (a child of each drivable car, `PlaceholderCar.damage`): health 100, a crash costs 3 per m/s over 6 m/s (60 km/h into a wall: about 32), weapon hits `vehicle_damage` per impact kind in `combat_config.json` (bullet 9, energy 11, blade 3, fist 1, paint 0). Stages: scuffed below 80, dented below 50, smoking below 25, wrecked at 0. Where a crash lands comes from the velocity change (`hit_point`). Tunables in `vehicle_damage.json`. Tests in `test_vehicle_damage.gd` and `test_weapons.gd`.
- [x] 1.2 Looks: scrape marks, dents (a per-car mesh copy only once dented, vertices pushed in around the hit, capped), cracked windscreen, a light out on a front or rear hit, engine smoke; smoking halves top speed and pull; tests (undamaged cars still share the mesh, the copy cap)
  - 2026-10-22: `VehicleMesh.dented` copies the car's own mesh (drivable cars build their own; traffic's shared mesh is untouched) and pushes vertices within 0.9 m of each dent inward (up to 0.3 m), with new flat normals and the paint scraped darker there; at most 8 dents kept. The paint dulls by stage. A front or rear hit once dented puts those lights out (`broken_light_material`, the headlight spots off). Smoking: soft engine smoke, half the pull and top speed. The cracked windscreen is left for later: the kit cars' glass shares the dark-parts surface. The dent cap for traffic is 1.5's. Mac screenshots (`--damage=80`): front corner pushed in, door creased, duller paint, tail lights dark, smoke.
- [x] 1.3 Wrecks by `outcomes.vehicle`: `conk_out` (clean: stalls, smoke puffs, mended by reset) and `burn` (smoke, then fire, then a blackened shell; dystopia sparks and white smoke); explosions for `burn` (a few seconds after burning: fling, damage cars in the radius so wrecks chain, hurt the player by distance, scorch); the player gets out of a wreck; mode schema and the three modes; tests in every tone
  - 2026-10-22: `outcomes.vehicle` in the tone schema and modes: clean `conk_out` (grey puffs, stalls, `can_enter`, a reset mends it), gritty `burn` (black smoke; fire 4 s later over the whole body with an orange light; explodes 6 s after that; a black shell that burns 40 s), dystopia `spark` (sparks and a thin white smoke, blue-white flames and blast). A mode without violence never burns. The blast (9 m): vehicles flung (up to 14,000 N·s) and damaged (up to 110, so a damaged neighbour is wrecked and burns in turn); `on_blast` listeners (the testbed): a flash, a fire burst, a scorch on the road, a boom voice, the player on foot thrown and hurt (up to 90), walkers within 6 m knocked down and everyone near running. The player gets out of a wreck that will burn once it is under 3 m/s and can't get back in. Mac screenshots: burning, the shell, dystopia's sparks.
- [ ] 1.4 Repair: reset keeps damage (except a clean wreck); a parking garage mends it unless the police see the car; tests
  - 2026-10-22: the reset part is done (reset keeps damage, a clean wreck is mended, a burning wreck stays put; tests). The garage is still to do.
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
