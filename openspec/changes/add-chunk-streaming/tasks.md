## 1. Streamer
- [x] 1.1 `ChunkStreamer`: wanted set by distance, worker-thread builds, per-frame add cap, spawn ring built synchronously; tests on a synthetic pack
- [x] 1.2 Detail tiers: near chunks with collision and LOD0, far chunks with far meshes only, upgrade/downgrade on movement, free beyond the far radius; tests

## 2. Integration
- [x] 2.1 Testbed drives the streamer from the players' positions; GLB cache path kept; benchmark prints time to first playable frame and chunks built

## 3. Verification
- [x] 3.1 Deck (2026-09-30, deck preset, 150 traffic + 120 pedestrians): first playable frame at 349 ms (spawn ring 5 chunks in 144 ms) against about 11 s before; 20 s benchmark while all 196 chunks streamed in: avg 7.46 ms, p99 12.46 ms, max 56 ms (chunk adds with collision on the main thread), GPU 6.70 ms, physics 7.71 ms. Steady-state after streaming not yet measured separately; hitch tuning (one add per frame, collision spread) is a follow-up
- [ ] 3.2 **Stop: human drives across the district on the Deck and watches for pop-in or hitches**
