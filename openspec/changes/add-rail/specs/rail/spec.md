## ADDED Requirements

### Requirement: Rail Import
The importer SHALL fetch railway ways and stations for the district, SHALL export them as a separate rail dataset with tracks, stations and lines, and SHALL keep rail out of the road graph.

#### Scenario: Confederation Line
- **WHEN** the Ottawa district is imported
- **THEN** `rail.v0.json` holds the light rail tracks with the Queen Street section flagged as tunnel, the stations with Lyon, Parliament and Rideau flagged underground, and one line listing the stations in order

#### Scenario: Road graph unchanged
- **WHEN** a district with rail is imported
- **THEN** the road graph contains no rail edges and the lane graph is identical to an import without the rail stage

### Requirement: Tracks And Stations
The game SHALL draw surface tracks as chunked ribbons with LODs and surface stations as platforms with canopies and name signs, SHALL lay rails flush across the road at level crossings, and SHALL draw nothing for tunnel tracks or underground stations.

#### Scenario: Surface station
- **WHEN** the player stands at Pimisi
- **THEN** a platform runs beside the track with a canopy and the station name

#### Scenario: Level crossing
- **WHEN** the player drives across a level crossing
- **THEN** the car rolls over two rails at road height with no ballast step

### Requirement: Trains On A Timetable
The host SHALL run trains along each line in both directions at the line's headway, slowing into and dwelling at stations, hidden while fully inside a tunnel, and clients SHALL mirror them from snapshots. Trains SHALL be solid to vehicles and SHALL NOT be enterable or takeable.

#### Scenario: Headway
- **WHEN** a line has a headway of 300 seconds
- **THEN** successive trains in one direction pass a platform about 300 seconds apart

#### Scenario: Dwell
- **WHEN** a train reaches a station
- **THEN** it stops beside the platform for the dwell time and then continues

#### Scenario: Cannot be entered
- **WHEN** the player presses interact next to a stopped train
- **THEN** nothing happens

#### Scenario: Deck budget
- **WHEN** two trains are within view on the Steam Deck
- **THEN** measured frame time stays within the 25 ms target
