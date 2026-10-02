## MODIFIED Requirements

### Requirement: Minimap
While driving, the HUD SHALL show a minimap: a crop of the overview map texture around the player, rotated to the car's heading, with no text, in both graphics presets. The minimap and the overview map SHALL draw the district boundary as a dashed line, and the HUD SHALL show a short district-edge notice once per approach when the player is within 80 m of the boundary and heading out of it.

#### Scenario: Turning
- **WHEN** the car turns 90 degrees to the right
- **THEN** the minimap rotates so the road ahead still points up

#### Scenario: Map open
- **WHEN** the overview map is open
- **THEN** the minimap is hidden

#### Scenario: Approaching the edge
- **WHEN** the player drives toward the boundary and comes within 80 m of it
- **THEN** the dashed boundary is visible on the minimap and the edge notice shows once, not again until the player has left and returned
