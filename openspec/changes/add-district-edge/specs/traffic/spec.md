## ADDED Requirements

### Requirement: Edge Turnaround
Traffic on a lane path that ends at a district edge closure SHALL slow and turn around a configured distance before the closure, and SHALL NOT spawn within a configured distance of it.

#### Scenario: Car near the edge
- **WHEN** a car's path ends at an edge closure 40 m ahead
- **THEN** the car slows, U-turns onto the opposing lane, and never reaches the closure

#### Scenario: Spawn exclusion
- **WHEN** the manager spawns traffic near a player standing at a closure
- **THEN** no agent appears within 60 m of the closure
