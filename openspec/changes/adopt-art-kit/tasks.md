## 0. Licence and pipeline
- [ ] 0.1 `game/assets/third_party/quaternius/` with per-pack `License.txt`, `SOURCE.md` and file list; `scripts/check-third-party.sh` (CC0 receipt present, size budget) in local and GitHub CI; `LICENSE-ASSETS` third-party section; tests on the check

## 1. Vehicles
- [ ] 1.1 Import the Cars and Public Transport packs (glTF, curated); `model` in the vehicle catalogue; `kit_vehicle.gd` (wheels and lights from named nodes); traffic MultiMeshes per model and LOD; liveries as overrides; tests
- [ ] 1.2 Screenshots before and after (lineup and street); Deck benchmark against main

## 2. People
- [ ] 2.1 Import the modular men and women (glTF parts, skeleton, animations); `kit_character.gd` assembling parts per profile; the player and actors on kit animations; tests
- [ ] 2.2 Crowd pools merged per look with bone indices; walk shader on the kit skeleton; ragdolls on the kit skeleton; tests (CPU against shader pose)
- [ ] 2.3 Prints and recolours; police, paramedic and gang looks; the creator on kit parts; children per the open question; screenshots in each tone; Deck benchmark with `--peds` at the cap

## 3. Trees and props
- [ ] 3.1 Kit trees and bushes in the vegetation MultiMeshes; kit street props (lamp posts, benches, hydrants, bins) in the dressing; tests; screenshots; Deck benchmark

## 4. Buildings
- [ ] 4.1 Facade tiling with kit pieces on OSM footprints (bays, floors, corners, doors and shops, roofs); tests; downtown screenshots; Deck benchmark
- [ ] 4.2 Roads, sidewalks and terrain restyled to the kit palette; screenshots

## 5. Verification
- [ ] 5.1 Human drives and walks Centretown on the Deck after each stage
