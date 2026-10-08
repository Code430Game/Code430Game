## 1. Data
- [x] 1.1 `factions.schema.v0.json`, `turf.schema.v0.json` (gains `faction` and `centre`), the base `factions.v0.json` with the Double Cross in three variants (five members and a leader), `faction_config.json`, `outcomes.gang` in the tone schema and mode files; validator checks factions (schema, descriptors, weapon ids, a lethal weapon in a non-lethal mode's variant); tests in `test_factions_data.py`
- [x] 1.2 The generator writes the turf's faction and centre; `overrides.json` may carry `turf`, which the importer writes out as `turf.v0.json` (test in `test_osm_pack.py`); the proving ground re-exported. The importer now records an input file's name, not its absolute path, so the committed pack regenerates byte for byte on any machine (the fresh-import test failed off the original worktree). The Ottawa Market turf is not placed: the Ottawa pack was off limits for this round; `--gang=N` tries the crew anywhere instead

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
