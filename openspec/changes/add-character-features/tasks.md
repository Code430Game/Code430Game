## 1. Body
- [ ] 1.1 `character_profile.gd`: new fields, names, defaults, random weights, `normalise` migration; tests on an old profile reproducing the old body
- [ ] 1.2 `character_mesh.gd`: garments, hair styles, hats, eyewear, accessories, patterns, face and build sliders; LOD1 and LOD2 builders; triangle-budget tests per LOD on the heaviest profile
- [ ] 1.3 `character_rig.gd`: three LOD instances with visibility ranges; player, remote players and the creator preview; test that ranges match the manager's

## 2. Pedestrians
- [ ] 2.1 `character_walk.gdshader` with bone index and tint masks in `CUSTOM0`, uniforms per pool; CPU vs shader pose test on one phase
- [ ] 2.2 `pedestrian_manager.gd`: pools per LOD, stride phase and amount in custom data, tints in instance colour, snapshot carries phase; tests on pool assignment and custom data

## 3. Creator
- [ ] 3.1 Pages with shoulder-button switching, new rows, preview LOD readout; `docs/controls.md`
- [ ] 3.2 Mac screenshots: a crowd walking on Rideau at LOD0, the same from 120 m, the creator's Clothes page

## 4. Verification
- [ ] 4.1 Deck: package, deploy, benchmark with `--peds` at the cap, before and after; draw calls and pedestrian `profile_line()` quoted
- [ ] 4.2 **Stop: human dresses a character on the Deck and walks a block watching the crowd move**
