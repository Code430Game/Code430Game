## 1. Generator
- [ ] 1.1 `tools/proving_ground/layout.py`: the loop, bridges, grid, highway stub with ramps, services, park, residential streets, dead end, bus loop, rail stub, spawn and start line in local metres; `emit.py` writes `osm.json` and the per-layer JSON files in the importer's shapes; `__main__.py` with `--out`; tests on the feature checklist (every feature present in the emitted data)
- [ ] 1.2 Importer: `--services-json` and `--vegetation-json`; `regions/proving-ground.json` with `dem: synthetic` and the file inputs; `scripts/regen-proving-ground.sh` runs the generator and the import; tests on the two new inputs
- [ ] 1.3 First export committed as `packs/proving-ground/`; pack validator green; validation report reviewed (no dead ends but the one at the edge, no one-way traps, every service placed); feature checklist test on the pack output

## 2. Game
- [ ] 2.1 `--pack=<id>` and `Settings.map_pack`; `PackLocator` finds the new pack from the repo and beside the executable; `deck-bench.sh --pack` and `--route loop`; tests
- [ ] 2.2 `LapTimer` from `lap.v0.json` (start line, direction, re-arm), HUD current and best lap on the loop only; schema and validator; tests on crossing, reverse, and hiding off the loop
- [ ] 2.3 CI job regenerates the pack and fails on a diff; `CONTRIBUTING.md` and the README say when to run the regen script
- [ ] 2.4 Mac screenshots: overhead of the whole district, the start line, the canal bridge, the grid crossing with signals, the police pad, the hospital bay; a lap driven with `--autodrive` (time noted)

## 3. Verification
- [ ] 3.1 Deck benchmark on the loop (`deck-bench.sh --pack code430.proving-ground --route loop`), numbers recorded as the quick-check baseline
- [ ] 3.2 **Stop: human drives laps of the loop on the Deck, visits each service, and says what is missing from the district**
