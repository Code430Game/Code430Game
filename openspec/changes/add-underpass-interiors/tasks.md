## 1. Content
- [ ] 1.1 `homelessness` descriptor in the closed list and the three mode files (clean none, gritty and dystopia strong); validator; migration note; tests

## 2. Tunnel dressing
- [ ] 2.1 `UnderpassBuilder`: emissive ceiling strip, grate and puddle at the low point, trench retaining walls with coping and the concrete shader; tests on wall extents and the low point
- [ ] 2.2 `underpass_lights` role with preset-gated OmniLights, always on; test on counts per preset

## 3. Sheltering population
- [ ] 3.1 Shelter spots and `ShelterProps` from tunnel ways, seeded, mode-gated; tests on spot placement and the clean mode producing nothing
- [ ] 3.2 `SHELTERING` pedestrians: rig sit and lie poses, host spawn at occupancy, snapshot pose index, walkers pass by; tests
- [ ] 3.3 Mac screenshots: the Chateau tunnel in gritty and in clean, a trench by Nicholas Street

## 4. Verification
- [ ] 4.1 Deck benchmark (`--benchmark=30 --autodrive`) plus a walk through the Chateau tunnel: frame avg and p99, GPU, draw calls against the bus round's 9.9 / 13.3 / 8.9 / 413
- [ ] 4.2 **Stop: human walks through the Chateau tunnel on the Deck in gritty, then switches to clean**
