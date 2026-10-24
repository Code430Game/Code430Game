## ADDED Requirements

### Requirement: Retaining Walls
The outer edge of a ground-level road is the outer edge of its sidewalk where it has one, else of its shoulder, else of the road. Where the terrain beside that edge, measured perpendicular to the road and away from it, starts to climb more steeply than 1 m for every 1.5 m out within 8 m of the edge, and the ground the wall would hold back stands more than 1 m for every 1.5 m out above the wall's foot (over 2.67 m at 4 m), the map SHALL have a vertical retaining wall, sampled every 2 m: at a sidewalk's outer edge where the climb starts within 4 m of it, else where the climb starts, as a straight line (a road's own grading keeps the ground level for 4 m past its edge and blends it over 3 m more, so a bank beside a bare road starts past that). Ground inside the grading zone of another road running alongside (the other carriageway of a split, a ramp beside its motorway, a motorway above its frontage road) is that road's surface or embankment, not a bank, and gets no wall. Stretches of wall shorter than 6 m SHALL be dropped. A wall SHALL rise from the ground in front of it up to the ground it holds back (behind a sidewalk, the highest ground within 8 m; beside a bare road, the ground 4 m behind, so no slot opens between the wall and the slope), or up to the soffit of a bridge deck the road passes under, whichever is lower, and never more than 8 m. The ground in front of a wall SHALL stay at the level of the road or sidewalk in front of it, and where the wall stands at a sidewalk's edge the first terrain cell behind it too, so no bank pokes through the sidewalk. A wall SHALL NOT cross any way that leaves the road: a road, a junction, a driveway or a path. Walls SHALL be written to `retaining_walls.v0.json`, each with `points`, `tops_m` (one height above each point, the same length as `points`) and `height_m` equal to the largest of them; the top between points and at chunk boundaries SHALL be interpolated linearly. A wall whose `tops_m` is missing or of the wrong length SHALL be rejected by the pack validator and skipped by the game. `barriers.v0.json` SHALL NOT carry walls, so a game that predates them ignores them.

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
