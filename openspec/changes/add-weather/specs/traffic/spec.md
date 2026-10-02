## ADDED Requirements

### Requirement: Weather Slows Traffic
Traffic agents SHALL scale their lane speed limit by the weather state's speed factor, so cars drive slower in rain, snow and fog.

#### Scenario: Snow on Bank Street
- **WHEN** the state is snow
- **THEN** every agent's target speed on a 50 km/h street is the configured snow factor of the dry limit
