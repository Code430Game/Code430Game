## 1. Body types and strings
- [x] 1.1 `character_profile.gd`: `body` field (a, b; migration to a), proportions table in `character_mesh.gd` with `a` reproducing today's body exactly, `b` built, sliders scaling from the table; `strings.v0.json` with mode variants and `ContentMode.text`; creator row reads the strings; tests on the old-profile mesh (vertex count and AABB unchanged), on `b`'s proportions, and on the labels per mode
- [x] 1.2 Officers and gang members pick from the pack's body split; `population` in pack data with the base default; tests

  - 2026-10-09: bodies are a per-bone shape (`CharacterMesh.BODIES`, `body_shape`). Torso parts stretch (shoulder width and chest depth on the spine, hip width on the pelvis), limbs move with their joint and slim about their own axis, and the head is untouched; bone pivots go through the same rule, so the skeleton, the posed mesh and the walk shader's pivots stay joined. Body A is the original body exactly (an old profile builds the same mesh). Body B: shoulders 0.82, hips 1.16, chest 1.06, limbs 0.86, drawn two height steps shorter. `random()` draws the body last, so every other field keeps its value for a seed. The split is `game/core/content/population.v0.json` (A 0.5, B 0.5); officers, gang members and pedestrians all take it through `CharacterProfile.random`. A map pack overriding it comes with the pack loader's content types, not yet. `scenes/character_lineup.tscn` shows each outfit on A and B side by side for screenshots

## 2. Children in clean mode
- [ ] 2.1 `minors` descriptor (levels none, present) in the closed list and the three mode files; migration note in the pack-format README; validator; tests on an old content file reading as none
- [ ] 2.2 `child` body row and pick lists; `CharacterProfile.child(rng)`; `PedestrianManager` child share gated by `allows("minors")` and `flag("violence")`, paired spawns; tests on every mode (none in gritty and dystopia whatever the pack says)
- [ ] 2.3 Untargetable: agent and body flag, `Shooter`, `hit_by_car` (obstacle stop, step aside), officer and gang pickers, the paint path; tests on each path in clean

## 3. Prints
- [ ] 3.1 `prints.schema.v0.json`, base `prints.v0.json`, validator (descriptors, variant cells in range); `tools/prints/build_atlas.py` for the three sheets, committed `prints.png`, CI diff check; font attribution in `LICENSE-ASSETS` and the base manifest once the human decides; tests on determinism and cell coverage
- [ ] 3.2 Builder UV2 regions on top, hood, cap and bag; shader atlas sample and tint LUT from the instance colour; `PedestrianManager` writes print index and tints; the gang's `look.print`; the player's and remote players' rigs pick their print from the profile; tests on UV2 regions and on the shader's pick per mode (bake and read back)

## 4. Garments, parts, LODs, creator
- [ ] 4.1 Garments, hair styles, hats, eyewear, accessories, patterns, face and build sliders; new fields and names; tests on the heaviest profile
- [ ] 4.2 LOD1 and LOD2 builders with triangle-budget tests; `character_rig.gd` three instances with ranges; pools per LOD in the manager; tests that ranges match
- [ ] 4.3 Creator pages on the shoulder buttons, the print picker, preview LOD readout; `docs/controls.md`
- [ ] 4.4 Mac screenshots: a crowd on Rideau in each mode (children only in clean, prints differing), the same crowd from 120 m, the creator's Body and Clothes pages in clean and gritty

## 5. Verification
- [ ] 5.1 Deck: package, deploy, benchmark with `--peds` at the cap in each mode, before and after; draw calls and the pedestrian `profile_line()` quoted
- [ ] 5.2 **Stop: human dresses a body A and a body B on the Deck, walks a block in clean and in gritty, and checks the prints and the crowd**
