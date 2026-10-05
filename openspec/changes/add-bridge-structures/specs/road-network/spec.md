## ADDED Requirements

### Requirement: Bridge Structures
The pack SHALL describe each bridge (its grouped deck edges, span, level, kind and ends, from `bridge=*` ways and `man_made=bridge` outlines), and the game SHALL draw each bridge as a solid deck with an underside, fascia, supports clear of the roads beneath it, and abutments. Walkways that belong to a bridge SHALL be drawn on its deck at deck height, and no sidewalk SHALL join a road on another layer.

#### Scenario: Looking up from under an overpass
- **WHEN** the player stands on a street under a highway bridge and looks up
- **THEN** they see the deck's concrete underside, not the sky

#### Scenario: No pier in a lane
- **WHEN** a bridge spans a street
- **THEN** no pier stands within 1.5 m of that street's ribbon or its sidewalks

#### Scenario: Walkway on the deck
- **WHEN** a footway tagged as part of a bridge runs beside its deck
- **THEN** it is drawn at the deck's height with the parapet outside it
- **AND** the sidewalks of the road under the bridge stay on the ground
