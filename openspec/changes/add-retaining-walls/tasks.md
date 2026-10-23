## 1. Importer
- [ ] 1.1 `walls.py`: wall lines along ground roads' outer edges (sidewalk, shoulder or road) where the finished terrain stands over `wall_min_m` above and rises steeper than `wall_slope`; joined and filtered by length; broken at junctions and at ways leaving the road; tops at the deck soffit under bridges, the ground behind elsewhere; tests
- [ ] 1.2 Terrain held at road or sidewalk level in front of each wall; `retaining_wall` barriers (top height per point) in `barriers.v0.json` and the schema; wall metres in the validation report; tests
- [ ] 1.3 Proving ground regenerated (Park Road under the motorway); Ottawa packs re-exported; `EdgeDropReport` before and after
## 2. Game
- [ ] 2.1 `BarrierBuilder`: `retaining_wall` as a concrete quad strip from the top line down to the ground line with a top face, collision, LODs; tests
- [ ] 2.2 Screenshots before and after: Metcalfe under the 417 (issue #167), Bank under the 417, Park Road on the proving ground
## 3. Checks
- [ ] 3.1 Deck benchmark at Metcalfe under the 417 against main
- [ ] 3.2 **Stop: the human drives and walks under the 417 on the Deck**
