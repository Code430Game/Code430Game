## ADDED Requirements

### Requirement: Sky Follows Weather
The sky, sun energy, ambient light and fog that follow the time of day SHALL also follow the weather state, blending the state's cloud coverage, tint and fog density on top of the hour's values.

#### Scenario: Fog at dawn
- **WHEN** the state is fog at sunrise
- **THEN** the horizon glow is muted, distance fog is dense and the sun disc is hidden
