# world-time Specification

## Purpose
A day-night clock that lights the city (sun, sky, lamps and headlights after dusk), shared by every peer in a co-op session.
## Requirements
### Requirement: Time Of Day
The world SHALL keep a time of day that advances at a configurable rate, and the sun's direction, energy and colour, the sky colours and the ambient light SHALL follow it, with a faint moon light at night.

#### Scenario: Noon and midnight
- **WHEN** the clock reads noon
- **THEN** the sun is high and bright; at midnight the sun is off and the scene is lit faintly and bluish

### Requirement: Lights After Dusk
Car lights, signal heads and building windows SHALL glow after dusk in proportion to how dark it is, and the player's car SHALL cast headlights.

#### Scenario: Dusk
- **WHEN** the sun drops below the horizon
- **THEN** car lights and windows light up and the player's headlights switch on

### Requirement: Shared Clock
In co-op the host's time of day SHALL be the session's time of day.

#### Scenario: Guest joins at night
- **WHEN** a guest joins a host whose clock reads 23:00
- **THEN** the guest's sky shows night within a few seconds

