## 1. Importer
- [x] 1.1 Fetch node tags; `control` per node, kept through clustering; schema; golden files; Ottawa refetched

## 2. Game
- [x] 2.1 `signal_controller.gd`: phases per signalised junction, offsets, config; tests (never two phases green, cycle advances)
- [x] 2.2 Traffic holds at red at the stop line and goes on green; full stop at stop signs; tests on a synthetic cross
- [x] 2.3 Signal poles and heads as MultiMeshes with instance colour; placed at approach corners

## 2b. Per-approach control (2026-10-01)
- [x] 2.4 Stops and signals tagged on the approach (OSM puts most stop signs a few metres before the node, with a direction) carry per edge end as `control_to` / `control_from`; a junction is signalised if any approach has signals; a stop applies only to the approaches that carry it (or all when the node is tagged). Stop sign posts with a red octagon per stop approach. Ottawa: 499 stop approaches (was 75 all-way nodes), 683 heads, 676 signs

## 3. Verification
- [x] 3.1 Deck (2026-09-30, idle Deck, 150 cars, 97 people, 550 heads): GPU 6.45 ms, render CPU 1.04 ms, physics 6.86 ms (traffic step 1.52 ms), draw calls 334, first playable 392 ms; downtown screenshot shows heads at the Bank Street junctions
- [x] 3.2 Human drove through the lights on the Deck (2026-10-02): "the lights look good, they're back to colours" after the lamp shader fix
