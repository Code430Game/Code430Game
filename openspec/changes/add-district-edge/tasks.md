## 1. Importer
- [ ] 1.1 `edge` attribute on roadblocks from `barriers.edge_style`; schema and validator; tests; Ottawa pack re-exported

## 2. Game
- [ ] 2.1 `EdgeClosureBuilder`: barricade row, cone taper, sign plate with `Label3D`, solid stop behind; `wall` keeps the slab; test on triangle counts and the stop's extent
- [ ] 2.2 Terrain fade to fog colour over the last 60 m to the bounds in both presets; district boundary on minimap and overview map; HUD edge notice once per approach; tests
- [ ] 2.3 Traffic: turnaround distance on edge lane paths, U-turn 40 m out, no spawns within 60 m; test that no agent reaches the closure
- [ ] 2.4 Mac screenshots: the 417 cut at the west bound, a downtown street end

## 3. Verification
- [ ] 3.1 Deck benchmark (`--benchmark=30 --autodrive`): frame avg and p99, GPU, draw calls against the bus round's 9.9 / 13.3 / 8.9 / 413
- [ ] 3.2 **Stop: human drives to the district edge on the Deck**
