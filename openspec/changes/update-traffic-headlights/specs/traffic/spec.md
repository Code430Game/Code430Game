## ADDED Requirements

### Requirement: Traffic Headlights At Night
After dusk, traffic cars near the player SHALL light the road ahead of them, and the nearest few (a number set by the graphics preset) SHALL carry a real light; by day none of this is drawn.

#### Scenario: A street at night
- **WHEN** the player stands by a street at 22:00 with traffic passing
- **THEN** each passing car lights a patch of road ahead of it

#### Scenario: Daytime
- **WHEN** the same street is seen at noon
- **THEN** no headlight pools or traffic lights are drawn
