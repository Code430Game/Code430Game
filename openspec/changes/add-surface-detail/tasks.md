## 1. Textures
- [ ] 1.1 Detail texture generator (asphalt, concrete, joint, paint) with presets; determinism test; materials sample world-space UVs on both presets; `docs/graphics-presets.md` updated

## 2. Sidewalks
- [ ] 2.1 `sidewalk_builder.gd`: distance-along and across in UV2; joint lines in the shader; longitudinal joint on wide ribbons; test on spacing; GLB export attribute and Ottawa pack re-exported

## 3. Crossings
- [ ] 3.1 Zebra stripe quads per crossing in the marking chunks, clipped to the curb, with a stop line on signalised approaches; tests on stripe count and extent
- [ ] 3.2 Mac screenshots: Bank and Somerset crossing, a Market sidewalk with joints, asphalt grain by day and at dusk on both presets

## 4. Verification
- [ ] 4.1 Deck benchmark on the usual route, both presets; no regression on `deck`
- [ ] 4.2 **Stop: human walks a crossing and a block of sidewalk downtown on the Deck**
