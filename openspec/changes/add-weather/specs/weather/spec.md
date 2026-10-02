## ADDED Requirements

### Requirement: Weather States From Data
The world SHALL run a weather state from a data table of states with coverage, precipitation, fog, wind and temperature, choosing the next state from seeded weighted transitions and blending between states over each state's transition time.

#### Scenario: Deterministic sequence
- **WHEN** two sessions start with the same weather seed and clock
- **THEN** they pass through the same sequence of states at the same times

#### Scenario: Pinned weather
- **WHEN** the testbed starts with `--weather=rain`
- **THEN** it rains for the whole session and the table is never consulted

### Requirement: Clouds In The Sky
The sky SHALL show a cloud layer whose coverage follows the weather state and drifts with the wind, dimming the sun as coverage rises; both presets SHALL declare their cloud layers and whether clouds cast shadows.

#### Scenario: Overcast noon
- **WHEN** the state is overcast at noon
- **THEN** the sky is mostly cloud, the sun is dimmer than on a clear noon and the clouds move

### Requirement: Precipitation And Surfaces
Rain and snow SHALL fall around the camera in proportion to the state's precipitation, roads SHALL darken and reflect while wet and dry out afterwards, and terrain, roofs and sidewalks SHALL whiten while snow lies and melt afterwards, with fog driving the distance fog.

#### Scenario: Rain at night
- **WHEN** it rains at night and the player's headlights are on
- **THEN** the road ahead shows the headlights reflected in a dark wet surface and rain streaks cross the view

#### Scenario: After the rain
- **WHEN** the state leaves rain
- **THEN** the road dries over the configured time back to its dry look

### Requirement: Weather Affects Driving
The player's car SHALL have less grip in rain and snow by the state's grip factor, identical in every preset, and the headlight auto mode SHALL switch the lights on in heavy rain, snow and fog.

#### Scenario: Braking on snow
- **WHEN** the player brakes hard on snow
- **THEN** the car slides further than on a dry road

### Requirement: Shared Weather
In co-op the host's weather state, seed and transition progress SHALL be the session's, sent with the clock.

#### Scenario: Guest joins in rain
- **WHEN** a guest joins a host where it is raining
- **THEN** the guest sees rain and wet roads within one clock sync interval
