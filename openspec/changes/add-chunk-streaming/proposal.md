# Change: Stream chunks around the players

**Status: proposed 2026-09-30 (queue item 2, approved in conversation: "lets build the next couple items").**

## Why
Every chunk of the district is built before the first frame: 196 chunks of terrain, roads,
buildings, sidewalks, barriers and collision. That is the ten-second start on the Deck, it
stalls the frame while it runs, and it caps the world at what fits in memory at once. The
constitution requires every world system to support 256 m chunked streaming.

## What Changes
- **ChunkStreamer** node owns the built chunks. Each frame it ranks chunks by distance to
  the anchors (players), builds the nearest missing ones on worker threads, and adds them to
  the scene on the main thread with a per-frame cap. The spawn ring (3x3) is built
  synchronously before the player is placed so there is ground under the car.
- **Detail tiers.** Chunks within the near radius carry everything including collision.
  Beyond it they carry only far meshes (terrain LOD1/LOD2, roads LOD1, buildings LOD1,
  water). A chunk is upgraded or downgraded as the anchors move. Beyond the far radius a
  chunk is freed.
- **GLB cache** still applies: a current cached chunk is imported instead of generated.
- **Testbed** uses the streamer; the benchmark reports chunks built and the time to first
  playable frame.
- **Not in this change:** threading the per-pack builders that run at load (markings,
  buildings, sidewalks, barriers), lazy map texture, multiple packs.

## Impact
- Affected specs: `world-streaming` (new).
- Affected code: `game/core/streaming/chunk_streamer.gd` (new), `map_pack.gd` (tiered
  `build_chunk`), `play_testbed.gd`, tests.
- Performance: time to first frame on the Deck measured before and after; frame time while
  driving checked for hitches (p99).
