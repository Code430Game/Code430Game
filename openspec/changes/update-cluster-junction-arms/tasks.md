## 1. Importer
- [ ] 1.1 `cluster.py`: straight-arm end placement with a snap tolerance; report field; `test_osm_cluster.py` divided-road parallel case; golden files re-baked with the diff reviewed
- [ ] 1.2 Ottawa pack re-exported; `road_graph.v0.json` at `c901050337` shows both Elgin carriageways passing the centroid at their own offset

## 2. Game
- [ ] 2.1 `junction_builder.gd`: arms from actual edge ends; offset-arm test; no non-simple polygon regressions in the Ottawa junction count (log the flagged count before and after)
- [ ] 2.2 Mac screenshots: Elgin and Nepean overhead and from the driver's seat, one divided primary crossing; minimap at both; traffic observed holding its lane through the junction

## 3. Verification
- [ ] 3.1 Deck benchmark on the usual autodrive route, no regression
- [ ] 3.2 **Stop: human drives Elgin through Nepean on the Deck (x 237, z 18) and watches the traffic there**
