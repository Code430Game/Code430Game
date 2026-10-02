## 1. Importer
- [ ] 1.1 Fetch `route=bus` relations; map members to edges with gap closing; stop matching; synthetic routes for uncovered corridors; `bus_routes` and the stop fields in the schema; validation report counts; golden tests on the fixture; Ottawa pack re-exported with the route count and gaps noted here

## 2. Game
- [ ] 2.1 `RoadGraph` loads routes; `TrafficAgent` route fields; route-following lane choice, rejoin and fallback; stops by route; terminus turn; placement by time on the host clock; `traffic_config.json` tunables; tests in `test_traffic.gd`
- [ ] 2.2 Destination sign: digit atlas, custom-data packing, bus mesh sign surface; sign in snapshots; tests on packing and `test_coop.gd` mirror
- [ ] 2.3 `BusStopBuilder`: shelters, poles, placards, collision, LODs, chunked with the dressing; tests
- [ ] 2.4 Mac screenshots: a numbered bus on the Transitway, a shelter on Albert Street

## 3. Verification
- [ ] 3.1 Deck benchmark on Albert and Slater with routes running; frame avg, p99, draw calls against the bus round (avg 9.9 ms, p99 13.3, 413 draws)
- [ ] 3.2 **Stop: human follows a numbered bus along its route on the Deck**
