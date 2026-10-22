## ADDED Requirements

### Requirement: Building Damage Marks
Buildings SHALL stay whole, and SHALL show damage as marks: a glass pane SHALL break when shot or hit hard, a hard crash SHALL leave a scrape or dent mark on a wall, and a burning wreck SHALL scorch what is beside it. Marks SHALL be visual only and capped.

#### Scenario: Shooting a window
- **WHEN** the player shoots a glass facade
- **THEN** that pane breaks with shards and a sound, and the building stays solid

#### Scenario: Shooting brick
- **WHEN** the player shoots a brick wall
- **THEN** a bullet hole is left as now and no pane breaks

#### Scenario: A car into a wall
- **WHEN** a car hits a wall hard
- **THEN** a scrape or dent mark is left on the wall where it hit
