## 1. Importer
- [ ] 1.1 `fetch.py`: railway query (ways, platforms, station nodes) cached beside the highway extract; `rail.py`: project, height, tunnel and bridge flags, lines with ordered stations, timetable defaults; validation report counts; tests on a fixture with one surface line, one tunnel and one level crossing
- [ ] 1.2 `pack.py`: flatten terrain under surface tracks, write `rail.v0.json`; schema in `docs/pack-format/`; pack validator accepts it; golden test; Ottawa pack re-exported (expect the Confederation Line surface on the Flats and east of uOttawa, the tunnel under Queen, Pimisi and uOttawa as surface stations)

## 2. Game
- [ ] 2.1 `RailData` loads `rail.v0.json`; `TrackBuilder` ribbons (LOD0 ballast, ties, rails; LOD1 strip; flush rails across level crossings) under the `rail_lod0` role; `StationBuilder` platforms, canopies and name signs; tests on triangle counts and crossing heights
- [ ] 2.2 `RailManager` and `train.tscn`: trains per line and direction at the headway, station approach and dwell, hidden in tunnels, bodies that hit the player's car; `--trains=` debug share; tests on spacing and dwell
- [ ] 2.3 Co-op: train snapshot in `world_sync.gd`, client mirror; test on round trip
- [ ] 2.4 Mac screenshots: a train on the Flats at Pimisi, the east portal by uOttawa

## 3. Verification
- [ ] 3.1 Deck benchmark (`--benchmark=30 --autodrive`): frame avg and p99, GPU, draw calls against the bus round's 9.9 / 13.3 / 8.9 / 413
- [ ] 3.2 **Stop: human watches a train pull into Pimisi and crosses the tracks on the Deck**
