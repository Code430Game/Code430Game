# emergency-services Specification

## Purpose
When someone is hurt, arrested or killed, the city responds: ambulances come to the injured, and a busted or wasted player is taken to the police station or the hospital and starts again.

## Requirements

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

### Requirement: Emergency Service Places
The pack SHALL list police stations, hospitals, fire stations, ambulance posts and helipads from OpenStreetMap with a kind, a name, a position and the nearest road node, keeping private and campus security apart from police; the maps SHALL show them with an icon per kind.

#### Scenario: Police headquarters on the map
- **WHEN** the player opens the map over Elgin Street
- **THEN** a police badge marks the Ottawa Police Headquarters and names it on hover

### Requirement: Respawn At Services
A busted player SHALL respawn outside the nearest police station and a wasted player outside the nearest hospital, falling back to the spawn point when the pack has none.

#### Scenario: Wasted near Saint-Vincent
- **WHEN** the player is wasted nearer Saint-Vincent Hospital than any other hospital
- **THEN** they respawn on the road outside Saint-Vincent Hospital
