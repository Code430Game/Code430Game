## ADDED Requirements

### Requirement: Footbridges And Skywalks
Pedestrian ways tagged as bridges SHALL keep their bridge flag and layer through the import, take their height from what they cross rather than the terrain, and be built as walkable decks with parapets, a roof where covered, and collision.

#### Scenario: Footbridge over a road
- **WHEN** a footway with `bridge=yes` and `layer=1` crosses a street
- **THEN** its deck sits above the street with clearance for traffic, ramps meet the ground ways at both ends, and the player can walk across it

#### Scenario: Footbridge over water
- **WHEN** a footway bridge crosses the canal
- **THEN** its deck is above the water surface and the player can cross without wading
