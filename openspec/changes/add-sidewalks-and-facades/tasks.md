## 1. Sidewalks
- [x] 1.1 Import: pedestrian ways carry width (tag or per-class default) and a `sidewalk` flag; terrain flattened under them; schema update
- [x] 1.2 `sidewalk_builder.gd`: ribbons with curb lift, chunked, colour per class; `sidewalks_lod0` in chunks and GLB
- [x] 1.3 Tests: width rules, ribbon winding, chunk assignment, GLB round trip

## 2. Facades
- [x] 2.1 Wall UVs in metres from the building extruder; roof UVs
- [x] 2.2 `facade.gdshader`: storey grid, window cells, four treatments, per-building seed via vertex colour alpha or custom data
- [x] 2.3 Treatment rules in data (type and height to treatment)
- [x] 2.4 Tests: UV extents match wall length and height, treatment selection

## 3. Verification
- [x] 3.1 Screenshots on Bank Street and Sparks Street; Deck render time (Steam Deck, deck preset, Bank Street: GPU 5.9 ms driving, 5.5 ms on foot, CPU 1.4 to 1.8 ms; load 6.1 s city build plus 4.5 s map texture without pre-built chunks)
- [ ] 3.2 **Stop: human walks a downtown block on the Deck**
