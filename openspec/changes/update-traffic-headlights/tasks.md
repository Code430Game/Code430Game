## 1. Headlights
- [x] 1.1 Light pools ahead of traffic cars near a player at night (one MultiMesh), real lights on the nearest per preset; tests; night screenshots before and after on the 417 and Metcalfe

## 2. Verification
- [ ] 2.1 Deck benchmark at night (`--extra "--time=22"`) against main
- [ ] 2.2 Human drives at night on the Deck
  - 2026-10-21 Deck: not passed: "Night is fine only you have headlights iirc", so traffic shows no headlights; to investigate.
  - 2026-10-21, checked on the Deck (main 6d84c1f, `--preset=deck --time=22`): traffic lights the road. Pools sit ahead of oncoming cars at street level and ahead of every car near the player from above; render cpu 1.48 ms, gpu 10.68 ms. Likely why it read as "only you": on the 417 most cars in view drive the player's way, so their pools are ahead of them, and the pools are faint beside the player's own beams. The human to look again at oncoming traffic, or say whether the pools should be brighter.
