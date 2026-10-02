## 1. Data
- [x] 1.1 Importer keeps bus-only ways and marks reserved lanes; bus stops exported; schema; tests; Ottawa pack re-exported (Lyon Street North, Transitway, Waller Street)

## 2. Game
- [x] 2.1 Reserved lanes in the lane graph, red strip paint, cars keep out, buses prefer them; test
- [x] 2.2 Bus agents: mesh, MultiMesh, bodies, lengths in following, stops with dwell, colours, no taking, snapshots; tests
- [x] 2.3 Mac screenshots (2026-10-02): Lyon Street North painted red with a bus coming down it; Transitway with buses at a high debug share (`--bus-share=`)

## 3. Verification
- [x] 3.1 Deck (2026-10-02): avg 9.9 ms, p99 13.3, GPU 8.9, draw calls 413; no regression
- [x] 3.2 Human followed a bus on the Deck (2026-10-02); asked for route numbers on the back and number plus route name on the front, taken into add-bus-routes
