## 1. Generator
- [x] 1.1 `dressing.py`: frontage lots with exclusions, zones, seeded variety, driveways, parking lots behind main-city blocks, tree rows on every avenue and the bank road, yard trees; `build(town=)` and `--town`; hooked before stitching (45 buildings to 1,989: 501 houses, 325 semi halves, 498 terrace units, 244 shops, 85 apartment and 37 commercial blocks, 4 towers, 219 offices, 15 warehouses; 2,142 row trees and 475 tagged trees; 168 driveways; 0.35 s to build)
- [x] 1.2 Tests: minimum building counts per zone (houses, semis or terraces, shops, apartments, offices, warehouses, towers), tree rows and yard trees, determinism, nothing placed inside an exclusion; pack regenerated with `scripts/regen-proving-ground.sh` and the pack test extended with the same minimums on the committed files (per chunk on the pack: at most 146 non-scatter trees against the deck cap of 400; bushes reach 1,849 in nine residential chunks against the cap of 600, so the cap trims them; at most 109 buildings)

## 2. Verification
- [ ] 2.1 Mac screenshots: overhead, the main city from the roundabout, a residential street, the bank road with its street trees, the greenbelt edge
- [ ] 2.2 Deck benchmark on the loop against the 2026-10-08 baseline (render cpu 1.10 / gpu 8.20 ms, physics 8.84 ms)
- [ ] 2.3 **Stop: human drives the dressed district on the Deck and says whether it reads as a town**
