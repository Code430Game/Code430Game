## 1. Generator
- [ ] 1.1 `dressing.py`: frontage lots with exclusions, zones, seeded variety, driveways, parking lots behind main-city blocks, tree rows on every avenue and the bank road, yard trees; `build(town=)` and `--town`; hooked before stitching
- [ ] 1.2 Tests: minimum building counts per zone (houses, semis or terraces, shops, apartments, offices, warehouses, towers), tree rows and yard trees, determinism, nothing placed inside an exclusion; pack regenerated with `scripts/regen-proving-ground.sh` and the pack test extended with the same minimums on the committed files

## 2. Verification
- [ ] 2.1 Mac screenshots: overhead, the main city from the roundabout, a residential street, the bank road with its street trees, the greenbelt edge
- [ ] 2.2 Deck benchmark on the loop against the 2026-10-08 baseline (render cpu 1.10 / gpu 8.20 ms, physics 8.84 ms)
- [ ] 2.3 **Stop: human drives the dressed district on the Deck and says whether it reads as a town**
