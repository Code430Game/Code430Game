## ADDED Requirements

### Requirement: Ambulance Response
When a pedestrian is knocked down, an ambulance SHALL drive from the nearest ambulance post or hospital to them, tend to them in a way that suits the tone, and return, with no more than two ambulances out at once.

#### Scenario: A pedestrian is hit by a car
- **WHEN** the player knocks a pedestrian down within 600 m of a hospital
- **THEN** an ambulance leaves that hospital with lights and siren, drives to the person on the roads, and paramedics tend to them

#### Scenario: Clean tone
- **WHEN** the ambulance reaches a downed person and the tone is clean
- **THEN** the person gets up and walks away

#### Scenario: Many people down
- **WHEN** five people are knocked down in different places
- **THEN** two ambulances are dispatched and the other calls wait in a queue
