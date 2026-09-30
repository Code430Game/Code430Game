## 0. Preconditions
- [x] 0.1 Human approves the proposal and the two open questions (2026-09-30, by ordering it third; recommendations taken)

## 1. Foundations
- [x] 1.1 `Players` autoload with register/local/all keyed by peer id; tests
- [x] 1.2 `player_config.tres` resource class with movement, camera, and entry tunables

## 2. Character
- [x] 2.1 `actors/player/player.tscn` CharacterBody3D with capsule, placeholder mannequin, camera-relative movement, run, jump, slopes
- [x] 2.2 Orbit camera on a SpringArm3D; handover to and from the chase camera
- [x] 2.3 gdUnit4 tests: movement speeds, slope climb, jump height, camera never inside geometry (scene runner)

## 3. Vehicles
- [x] 3.1 `Seat` marker and `driver_peer_id` on the placeholder car; input routes only to the driven car
- [x] 3.2 Enter and exit with the interact action; refusal at speed; safe exit placement
- [x] 3.3 Tests: enter within range, refuse out of range, exit placement on flat and sloped ground

## 4. Testbed
- [x] 4.1 Rename to `play_testbed`, start on foot beside the car, `--drive` flag for benchmarks
- [x] 4.2 Minimap and map follow the controlled body
- [x] 4.3 HUD prompt "Y enter" near a car; no other on-screen text while playing

## 5. Verification
- [x] 5.1 Deck run: walk, enter, drive, exit; record frame time (Steam Deck, deck preset: on foot beside the car avg 5.3 ms, driving 5.7 ms, p99 6.1 ms; the agent ran the enter/exit round trip headless in tests, the human's walk is task 5.2)
- [ ] 5.2 **Stop: human walks around the ByWard Market and gets back in the car on the Deck**
