## 1. Importer
- [x] 1.1 `cluster.py`: straight-arm end placement with a snap tolerance; report field; `test_osm_cluster.py` divided-road parallel case; golden files re-baked with the diff reviewed
- [x] 1.2 Ottawa pack re-exported; `road_graph.v0.json` at `c901050337` shows both Elgin carriageways passing the centroid at their own offset

## 2. Game
- [x] 2.1 `junction_builder.gd`: arms from actual edge ends; offset-arm test; no non-simple polygon regressions in the Ottawa junction count (log the flagged count before and after)
  - Hull-fallback (flagged) junctions in Ottawa, 917 built: 70 before (22 clusters), 58 after (10 clusters). 14 clusters now walk a simple polygon; 2 newly fall back to the hull (`c1194392166` Wellington/Booth: a 0.14 m fillet folds across a cap; `c1236845823` Chamberlain/Percy: a jogged leg starts inside the cross street's ribbon). Non-cluster junctions unchanged.
- [ ] 2.2 Mac screenshots: Elgin and Nepean overhead and from the driver's seat, one divided primary crossing; minimap at both; traffic observed holding its lane through the junction

## 3. Verification
- [ ] 3.1 Deck benchmark on the usual autodrive route, no regression
- [ ] 3.2 **Stop: human drives Elgin through Nepean on the Deck (x 237, z 18) and watches the traffic there**
