## 1. Measure
- [ ] 1.1 Branch from `fix/road-edge-drops`; `MAX_POKING_SHARE` back to 0.01; run `scripts/terrain-trial.sh centretown` on the branch as is and record the numbers here
## 2. Junction ground
- [ ] 2.1 Junction outlines and per-vertex heights in the importer, matching `JunctionBuilder` (approach (a) in design.md, or (b) with a reason); a test that they match the game's on the proving ground
- [ ] 2.2 Terrain under each outline (plus its margin) flattened to the junction surface; roads own only the ground outside outlines; tests (two arms at different heights: no trap at either arm's edge, no poke in the corner)
- [ ] 2.3 Re-check the bridge pieces (deck-end fence at ground ends, under-deck alongside only, roads beneath own their beds, deck-height beds not raised under decks) and the sidewalk cap and cut; keep what is still needed; tests
## 3. Prove it
- [ ] 3.1 The bar in design.md met on Centretown; the Glebe and Hintonburg traps down with no new junction pokes; proving ground regenerated; local CI green
- [ ] 3.2 Packs exported from a clean commit (versions per proposal.md) into a scratch folder and put on the Deck build (`scripts/package.sh linux`, swap the three folders under `build/linux/packs/`, `scripts/deploy-deck.sh`)
- [ ] 3.3 **Stop: the human drives the places in design.md on the Deck**
## 4. Release
- [ ] 4.1 Location-OttawaOnCa PR with the three packs and `code430.json`'s `game_commit`; the human merges; tags; the game's `packs.lock.json` updated; game PR (importer, scan, lock)
