## ADDED Requirements

### Requirement: Bus Stops On The Street
Every bus stop in the map pack SHALL be built on the sidewalk side as a shelter when the stop is tagged with one, else a pole with a flag, each carrying a placard with the route numbers that serve it, chunked with the street dressing with collision and LODs.

#### Scenario: Sheltered stop
- **WHEN** a stop tagged `shelter=yes` lies beside a sidewalk ribbon
- **THEN** a glass shelter with a roof and bench stands on the sidewalk aligned to the kerb, with its route numbers on the placard

#### Scenario: Flag stop
- **WHEN** a stop has no shelter tag
- **THEN** a pole with a flag sign and placard stands at the stop
