## 1. Profile, body, store
- [x] 1.1 `character_profile.gd`: fields, palettes, random, normalise, step; tests
- [x] 1.2 `character_mesh.gd`: blocky body from a profile, height and build scaling, eyes on the -Z face; test on bounds
- [x] 1.3 `character_store.gd`: last + presets in `user://characters.json`; first start random; tests on round trip
- [x] 1.4 Player and RemotePlayer wear the body; profile sent with hello/welcome and on change

## 2. Creator screen
- [x] 2.1 Pause menu "Character" opens the creator; rows, preview viewport, randomise, presets, done
- [x] 2.2 Controls doc; Mac screenshots of the body on foot and the creator checked (2026-10-01)

## 3. Verification
- [x] 3.1 Deck benchmarks in the later rounds carried the creator (buses round 2026-10-02: avg 9.9 ms, p99 13.3); no regression attributed to it
- [x] 3.2 Human: "the character creator seems fine" (Deck, 2026-10-02); co-op view deferred to the co-op change
