## 0. Licence and pipeline
- [x] 0.1 `art/quaternius/<pack>/` (unmodified sources) with `SOURCE.md` (licence, links, date, sha256 list) and the pack's `License.txt` or a receipt section; built models in `game/assets/` beside a `SOURCE.md`; `scripts/check-third-party.sh` (`tools/third_party_check.py`: CC0 receipt, listed hashes, 120 MB budget) in `scripts/ci-local.sh`; `LICENSE-ASSETS` third-party section; tests on the check. The Cars Pack's own `License.txt` is still to add: its Drive folder was over quota on 2026-10-10, so the `.glb` files came from Poly Pizza (CC0, by Quaternius) and the receipt links the pack, itch.io and Poly Pizza pages

## 1. Vehicles
- [x] 1.1 Cars Pack imported; `tools/vehicle_kit` (Blender script from `recipes.json`: light wheels, `Paint` material, scale, and the ambulance, van, box truck and pickup derived from the kit SUV) with `scripts/build-vehicles.sh` and `apply_dims.py`; `model` in the catalogue and schema; `kit_vehicle.gd` rebuilding a model into VehicleMesh's four surfaces at LOD0 (traffic, parked cars, the player's car); tests. The bus waits for the Public Transport pack (Drive quota); the player's wheel nodes keep the cylinder wheels
- [x] 1.2 Screenshots before and after (lineup and street): done 2026-10-10 on the Mac (frame avg 19.1 vs 18.8 ms, draw calls 1,309 both); Deck benchmark against main below. One branch run had a single 2 s physics hitch that three more runs of the same build did not repeat (render cpu 1.76 / gpu 12.21 ms, physics mean 13.06 ms, max 25 ms, against main's 1.73 / 12.05 / 12.28)
  - 2026-10-10 Deck benchmark (scripts/deck-bench.sh, median of 2, `--benchmark=40 --autodrive --preset=deck`): main c2500cb: render cpu 1.73 / gpu 12.05 ms measured, physics mean 12.28 ms (max 27.92), frame avg 13.62 / p99 23.13 ms (paced), first playable 869 ms; change/adopt-art-kit-vehicles 1cfa903: render cpu 1.88 / gpu 12.57 ms measured, physics mean 22.71 ms (max 1017.93), frame avg 14.24 / p99 24.97 ms (paced), first playable 897 ms.
- [ ] 1.3 Round 2 (the human): nudge the derived vehicles in `recipes.json` (taller cab, box from the skirt); the Public Transport bus; kit wheels on the player's wheel nodes

## 2. People
- [x] 2.1 Modular men and women imported (master `.blend` per pack with its `License.txt`; the Cars Pack's `License.txt` added too); `tools/people_kit` (Blender, `recipes.json`) moving faces, hair, beards, hats and eight outfits per body onto the game's rig (see design.md: not the kit skeleton or animations) with `scripts/build-people.sh`; `kit_character.gd` assembling a profile's parts in `CharacterMesh`, kit pivots for the rig, crowd shader and ragdolls; `outfit` in the profile and creator, kit names for hair, beards, hats and outfits; officers in the uniform, paramedics in work clothes, the gang in its named outfit (`look.outfit`); tests
- [ ] 2.2 The crowd pools, walk shader and ragdolls already wear the kit through 2.1 (same rig, kit pivots). Left: the kit's own animations (run, punch, death) where they beat the procedural ones, and a lighter crowd level of detail if the Deck needs it; tests
- [ ] 2.3 Prints and recolours; police, paramedic and gang looks; the creator on kit parts; children per the open question; screenshots in each tone; Deck benchmark with `--peds` at the cap

## 3. Trees and props
- [ ] 3.1 Kit trees and bushes in the vegetation MultiMeshes; kit street props (lamp posts, benches, hydrants, bins) in the dressing; tests; screenshots; Deck benchmark

## 4. Buildings
- [ ] 4.1 Facade tiling with kit pieces on OSM footprints (bays, floors, corners, doors and shops, roofs); tests; downtown screenshots; Deck benchmark
- [ ] 4.2 Roads, sidewalks and terrain restyled to the kit palette; screenshots

## 5. Verification
- [ ] 5.1 Human drives and walks Centretown on the Deck after each stage
