## 1. Importer
- [x] 1.1 Class `parking` in `road_classes.json`; aisles and driveways kept with widths and speed; `drive-through` and `emergency_access` still dropped; schema enum; graph tests; validation report lists the class separately and recounts islands; done 2026-10-04: on the Metcalfe/417 fixture, 60 parking edges join the streets; the network stays one component; likely-real dead ends 13 → 4 (driveways reconnect service roads); 32 parking dead ends counted apart; boundary dead ends unchanged at 17; goldens re-baked. Ottawa islands recounted with the 1.2 re-export
- [ ] 1.2 `parking.py`: fetch lots (ways and relations), rings clipped, kind, capacity, access, fee, operator, orientation, `stall_dir` from aisles, entrances, ground height; street-side bays from `parking:*` tags; `parking.v0.json` and schema; `pack_tools` validates it; tests on a fixture with a lot with an aisle, a lot without, a diagonal lot and a street with bays; golden files re-baked; Ottawa pack re-exported with the lot, bay and stall counts noted here

## 2. Lanes
- [ ] 2.1 `parking_only` on lane paths and connectors from class `parking`; `choose_next`, spawning and bus routing skip them; the player's car drives them; tests

## 3. Game
- [ ] 3.1 `parking_lot_builder.gd`: slab, kerb, stall markings by orientation, curb stops, entrance sign with operator text; map fill; tests on stall layout for the fixture lots
- [ ] 3.2 `parked_cars.gd` and `parking_config.json`: seeded occupancy by hour, catalogue classes, per-chunk MultiMeshes with LODs and caps per preset, bodies from the pool, `--parking-occupancy=`; taking a parked car; tests on determinism and caps
- [ ] 3.3 Mac screenshots: a Market lot by day and at night, a Queensway lot, a residential street with bays, the map with lots

## 4. Verification
- [ ] 4.1 Deck benchmark on the usual route plus a pass through the Market lots; counts and frame time recorded here
- [ ] 4.2 **Stop: human pulls into a lot, parks, takes a parked car and drives out on the Deck**
