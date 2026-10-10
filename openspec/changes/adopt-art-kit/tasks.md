## 0. Licence and pipeline
- [x] 0.1 `art/quaternius/<pack>/` (unmodified sources) with `SOURCE.md` (licence, links, date, sha256 list) and the pack's `License.txt` or a receipt section; built models in `game/assets/` beside a `SOURCE.md`; `scripts/check-third-party.sh` (`tools/third_party_check.py`: CC0 receipt, listed hashes, 120 MB budget) in `scripts/ci-local.sh`; `LICENSE-ASSETS` third-party section; tests on the check. The Cars Pack's own `License.txt` is still to add: its Drive folder was over quota on 2026-10-10, so the `.glb` files came from Poly Pizza (CC0, by Quaternius) and the receipt links the pack, itch.io and Poly Pizza pages

## 1. Vehicles
- [x] 1.1 Cars Pack imported; `tools/vehicle_kit` (Blender script from `recipes.json`: light wheels, `Paint` material, scale, and the ambulance, van, box truck and pickup derived from the kit SUV) with `scripts/build-vehicles.sh` and `apply_dims.py`; `model` in the catalogue and schema; `kit_vehicle.gd` rebuilding a model into VehicleMesh's four surfaces at LOD0 (traffic, parked cars, the player's car); tests. The bus waits for the Public Transport pack (Drive quota); the player's wheel nodes keep the cylinder wheels
- [ ] 1.2 Screenshots before and after (lineup and street): done 2026-10-10 on the Mac (frame avg 19.1 vs 18.8 ms, draw calls 1,309 both); Deck benchmark against main pending
- [ ] 1.3 Round 2 (the human): nudge the derived vehicles in `recipes.json` (taller cab, box from the skirt); the Public Transport bus; kit wheels on the player's wheel nodes

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
