## ADDED Requirements

### Requirement: Retaining Walls
The outer edge of a ground-level road is the outer edge of its sidewalk where it has one, else of its shoulder, else of the road. Where the terrain 4 m out from that edge, measured perpendicular to the road and away from it, stands more than 1.0 m above the edge and rises more steeply than 1 m for every 1.5 m out, the map SHALL have a vertical retaining wall along that edge, sampled every 2 m. Stretches of wall shorter than 6 m SHALL be dropped. A wall SHALL rise from the ground in front of it up to the ground behind it, or up to the soffit of a bridge deck the road passes under, whichever is lower. The ground in front of a wall SHALL stay at the level of the road or sidewalk in front of it. A wall SHALL NOT cross any way that leaves the road: a road, a junction, a driveway or a path. Walls SHALL be written to `retaining_walls.v0.json`, each with `points`, `tops_m` (one height above each point, the same length as `points`) and `height_m` equal to the largest of them; the top between points and at chunk boundaries SHALL be interpolated linearly. A wall whose `tops_m` is missing or of the wrong length SHALL be rejected by the pack validator and skipped by the game. `barriers.v0.json` SHALL NOT carry walls, so a game that predates them ignores them.

#### Scenario: Driving under the 417 on Metcalfe
- **WHEN** the player drives or walks Metcalfe Street under the 417
- **THEN** concrete walls rise straight up beside the sidewalks to the deck, and no grass slope reaches the sidewalks or the road

#### Scenario: A side street through the wall
- **WHEN** a side street, a driveway or a path leaves a road where a retaining wall runs
- **THEN** the wall stops either side of it, and the way is open

#### Scenario: A gentle bank
- **WHEN** the ground beside a road rises gently (a lawn or a shallow embankment)
- **THEN** there is no wall, and the ground meets the road or sidewalk as before

#### Scenario: An older game loads a pack with walls
- **WHEN** a game built before retaining walls loads a pack that has `retaining_walls.v0.json`
- **THEN** it loads the pack without walls, and builds no wall at the wrong height
