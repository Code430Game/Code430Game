## 0. Preconditions
- [ ] 0.1 Human approves the proposal and the two open questions

## 1. Foundations
- [ ] 1.1 `Players` autoload with register/local/all keyed by peer id; tests
- [ ] 1.2 `player_config.tres` resource class with movement, camera, and entry tunables

## 2. Character
- [ ] 2.1 `actors/player/player.tscn` CharacterBody3D with capsule, placeholder mannequin, camera-relative movement, run, jump, slopes
- [ ] 2.2 Orbit camera on a SpringArm3D; handover to and from the chase camera
- [ ] 2.3 gdUnit4 tests: movement speeds, slope climb, jump height, camera never inside geometry (scene runner)

## 3. Vehicles
- [ ] 3.1 `Seat` marker and `driver_peer_id` on the placeholder car; input routes only to the driven car
- [ ] 3.2 Enter and exit with the interact action; refusal at speed; safe exit placement
- [ ] 3.3 Tests: enter within range, refuse out of range, exit placement on flat and sloped ground

## 4. Testbed
- [ ] 4.1 Rename to `play_testbed`, start on foot beside the car, `--drive` flag for benchmarks
- [ ] 4.2 Minimap and map follow the controlled body
- [ ] 4.3 HUD prompt "Y enter" near a car; no other on-screen text while playing

## 5. Verification
- [ ] 5.1 Deck run: walk, enter, drive, exit; record frame time
- [ ] 5.2 **Stop: human walks around the ByWard Market and gets back in the car on the Deck**
