## ADDED Requirements

### Requirement: Junction Control From Data
The importer SHALL export a control type for every node (signals, stop, give way or none) from its OSM tags, and clustering SHALL keep a control present on any merged node.

#### Scenario: Signalised cluster
- **WHEN** one of the nodes merged into a junction cluster is tagged as traffic signals
- **THEN** the cluster node's control is signals

### Requirement: Signal Cycles
Each signalised junction SHALL run a two-phase cycle over its approach axes with green, amber and all-red intervals from config, offset per junction, and no two conflicting phases SHALL be green at once.

#### Scenario: Cross
- **WHEN** a four-way signalised junction runs
- **THEN** the north-south and east-west phases alternate and are never green together

### Requirement: Traffic Obeys Control
A traffic car approaching a red or amber signal SHALL stop at the junction's stop line and proceed on green; a car at a stop sign SHALL come to a full stop before entering the junction.

#### Scenario: Red light
- **WHEN** a traffic car reaches a junction whose phase for its approach is red
- **THEN** it stops before the stop line and moves on when the phase turns green

### Requirement: Signal Heads
Signalised junctions SHALL show a pole and head at each approach whose colour is the approach's current light.

#### Scenario: Visible state
- **WHEN** an approach's phase is green
- **THEN** its head shows green and the crossing approaches' heads show red
