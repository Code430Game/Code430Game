## 1. Streamer
- [x] 1.1 `ChunkStreamer`: wanted set by distance, worker-thread builds, per-frame add cap, spawn ring built synchronously; tests on a synthetic pack
- [x] 1.2 Detail tiers: near chunks with collision and LOD0, far chunks with far meshes only, upgrade/downgrade on movement, free beyond the far radius; tests

## 2. Integration
- [x] 2.1 Testbed drives the streamer from the players' positions; GLB cache path kept; benchmark prints time to first playable frame and chunks built

## 2b. Hitch work (2026-10-01)
- [x] 2.2 Streamed chunks land in pieces (empty node, meshes two per frame, worker-built collision shapes one per frame). Deck downtown: frames with over 8 ms of streaming work 130 -> 17 per 20 s run, p95 21 -> 16 ms, p99 37 -> 20 ms, worst 71 -> 42 ms. Remaining worst cases are a single shape attach (38 ms, Jolt builds on attach) and the first chunk add (26 ms, shader warm-up)

## 3. Verification
- [x] 3.1 Deck (2026-09-30, deck preset, 150 traffic + 120 pedestrians): first playable frame at 349 ms (spawn ring 5 chunks in 144 ms) against about 11 s before; 20 s benchmark while all 196 chunks streamed in: avg 7.46 ms, p99 12.46 ms, max 56 ms (chunk adds with collision on the main thread), GPU 6.70 ms, physics 7.71 ms. Steady-state after streaming not yet measured separately; hitch tuning (one add per frame, collision spread) is a follow-up
- [x] 3.2 Human (Deck, 2026-10-02): nothing noticed while driving the district; no pop-in or hitch reported
