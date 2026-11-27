## ADDED Requirements

### Requirement: Retaining Walls
The outer edge of a ground-level road is the outer edge of its sidewalk where it has one, else of its shoulder, else of the road. Where the terrain beside that edge, measured perpendicular to the road and away from it, starts to climb more steeply than 1 m for every 1.5 m out within 8 m of the edge, and the ground 4 m into that climb stands more than 1 m for every 1.5 m out above the edge (over 2.67 m), the map SHALL have a vertical retaining wall, sampled every 2 m. The wall's line SHALL run parallel to the road wherever the climb starts: at the sidewalk's outer edge, or 4 m out from a bare road's edge (the end of the level margin the road's own grading keeps), moving from one to the other no faster than 1 m for every 4 m along. Ground inside the grading zone of another road running alongside (the other carriageway of a split, a ramp beside its motorway, a motorway above its frontage road) is that road's surface or embankment, not a bank, and gets no wall. A stretch SHALL get no wall where, at more than half its stations, the ground 3 m behind the wall's line is still level with the foot (within 0.5 m: a verge or a lawn, so the bank has room to slope) or lies more than 0.75 m below it within those 3 m (a ditch: the bank is across it, not at the road). Stretches of wall shorter than 6 m or lower than 1.5 m SHALL be dropped, and so SHALL walls that follow on end to end and together are shorter than 12 m.

A wall SHALL hold back the ground behind it. The ground in front of a wall SHALL stay at the level of the road or sidewalk in front of it, and so SHALL every terrain cell that touches the wall's face, so no bank reaches the sidewalk or pokes through the wall. Behind that the ground SHALL be raised to the wall's top where it stood lower, so the bank carries on from the top of the wall. The wall SHALL be solid from its face back over the strip where the terrain grid climbs from the foot to the top, with a level top a player can stand on: there SHALL be no slot between a wall and the ground behind it. A wall's top SHALL be the ground 4 m into the climb, or the bank's crest where that is within 2 m above it, or the soffit of a bridge deck the road passes under where the bank climbs to the deck, and never more than 8 m; tops SHALL be smoothed along the wall and come down to the ground at an end where the wall stops, and no top SHALL stand above the ground behind the wall's solid top. A wall SHALL NOT cross any way that leaves the road (a road, a junction, a driveway or a path), and SHALL NOT cover a lower road, junction or path behind it.

Walls SHALL be written to `retaining_walls.v0.json`, each with `points`, `tops_m` (one height above each point, the same length as `points`), `height_m` equal to the largest of them, `side` (the side of the points' direction the held-back ground is on) and `cap_m` (how far behind the face the solid top reaches); the top between points and at chunk boundaries SHALL be interpolated linearly. A wall whose `tops_m` is missing or of the wrong length SHALL be rejected by the pack validator and skipped by the game. `barriers.v0.json` SHALL NOT carry walls, so a game that predates them ignores them.

#### Scenario: Driving under the 417 on Metcalfe
- **WHEN** the player drives or walks Metcalfe Street under the 417
- **THEN** concrete walls rise straight up beside the sidewalks to the deck, and no grass slope reaches the sidewalks or the road

#### Scenario: A side street through the wall
- **WHEN** a side street, a driveway or a path leaves a road where a retaining wall runs
- **THEN** the wall stops either side of it, and the way is open

#### Scenario: On top of a wall
- **WHEN** the player walks from the bank onto the top of a retaining wall, or drops onto it
- **THEN** they stand on ground level with the wall's top right up to its face, and there is nowhere behind the wall to fall into or be stuck in

#### Scenario: A wall along a curving road
- **WHEN** a retaining wall runs beside a road whose bank starts nearer or further along the way
- **THEN** the wall keeps one distance from the road, as straight or as curved as the road, and its top rises and falls gently, not cell by cell

#### Scenario: A gentle bank
- **WHEN** the ground beside a road rises gently (a lawn or a shallow embankment)
- **THEN** there is no wall, and the ground meets the road or sidewalk as before

#### Scenario: A lawn before the bank
- **WHEN** level ground 3 m or more wide lies between a sidewalk and the bank behind it (the lawn of Parliament Hill along Wellington Street)
- **THEN** there is no wall at the sidewalk, and the bank slopes as the land does

#### Scenario: No slab on its own
- **WHEN** a bank is steep enough for a wall over less than 12 m of a road
- **THEN** there is no wall there

#### Scenario: An older game loads a pack with walls
- **WHEN** a game built before retaining walls loads a pack that has `retaining_walls.v0.json`
- **THEN** it loads the pack without walls, and builds no wall at the wrong height
