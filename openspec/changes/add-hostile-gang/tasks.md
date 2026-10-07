## 1. Data
- [ ] 1.1 `factions.schema.v0.json`, `turf.schema.v0.json`, the base `factions.v0.json` with the first gang in three variants, `faction_config.json`; `overrides.json` gains `turf`; validator checks (descriptors, lethal variants, turf ring); tests
- [ ] 1.2 Proving ground generator writes the turf; an Ottawa turf in `overrides.json` around the Market for trying it there; both packs re-exported (the proving ground via its regen script)

## 2. Members
- [ ] 2.1 Members as pedestrians with a faction and a held weapon: spawn in turf to the cap, patrol pairs on the walk graph, the gang car on the lanes; snapshot stride; the Shooter and fists reach them; tests
- [ ] 2.2 Threat machine (patrol, alert with warning, attack with melee and the ranged variant, flee, regroup), reactions from `outcomes.gang`, downed members respawn after the cooldown; tests in every tone
- [ ] 2.3 Gang heat per player with the HUD glyph, the gang car sent at full; legend entry; tests

## 3. Police and co-op
- [ ] 3.1 Member gunfire reports as the member's; officers fight members when `officers_fight_gang`; tests
- [ ] 3.2 Host-only simulation, members in the pedestrian snapshots, hits through `report_shot`; tests in one process
- [ ] 3.3 Mac screenshots: the warning, a fight in the proving ground turf in each tone, officers arriving, the heat glyph; `--gang=N` and `--turf-log` documented in CONTRIBUTING

## 4. Verification
- [ ] 4.1 Deck benchmark in the turf during a fight (proving ground, then the Market turf)
- [ ] 4.2 **Stop: human walks into the turf on the Deck in gritty and in clean, fights, runs, and says whether the gang is fun and fair**
