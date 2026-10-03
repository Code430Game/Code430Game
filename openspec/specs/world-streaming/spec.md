# world-streaming Specification

## Purpose
TBD - created by archiving change add-chunk-streaming. Update Purpose after archive.
## Requirements
### Requirement: Chunks Stream Around Players
The world SHALL be built in 256 m chunks on demand, nearest to the players first, on worker threads, with a bounded number of chunks added to the scene per frame. The chunks around each player's spawn SHALL exist before the player is placed.

#### Scenario: Start
- **WHEN** the game starts
- **THEN** the player stands on built ground within the first frame and the remaining chunks appear over the following seconds, nearest first

### Requirement: Detail Tiers
Chunks within the near radius of a player SHALL carry full detail and collision; chunks beyond it SHALL carry only far-distance meshes; chunks beyond the far radius SHALL be freed. Tiers SHALL follow the players as they move.

#### Scenario: Driving away
- **WHEN** a player drives more than the near radius from a chunk
- **THEN** that chunk drops its collision and near meshes but keeps its far meshes until the player passes the far radius

