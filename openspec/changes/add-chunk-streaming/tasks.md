## 1. Streamer
- [x] 1.1 `ChunkStreamer`: wanted set by distance, worker-thread builds, per-frame add cap, spawn ring built synchronously; tests on a synthetic pack
- [x] 1.2 Detail tiers: near chunks with collision and LOD0, far chunks with far meshes only, upgrade/downgrade on movement, free beyond the far radius; tests

## 2. Integration
- [x] 2.1 Testbed drives the streamer from the players' positions; GLB cache path kept; benchmark prints time to first playable frame and chunks built

## 3. Verification
- [ ] 3.1 Deck: time to first frame and driving p99 recorded before and after
- [ ] 3.2 **Stop: human drives across the district on the Deck and watches for pop-in or hitches**
