## ADDED Requirements
### Requirement: Race Tracks
The importer SHALL import `highway=raceway` ways as drivable roads with their own defaults: three lanes, one-way unless tagged otherwise, the OSM `width` when tagged, and a `max_grade` of 0.20. It SHALL give every raceway inside a named motorsport facility the facility's name as its `circuit`. The game SHALL spawn no traffic, parked cars or pedestrians on a raceway, and SHALL build no sidewalks, lane markings or street furniture on one.

#### Scenario: Calabogie imported
- **WHEN** the Calabogie region is exported
- **THEN** the 4,994 m circuit loop and its pit lane are drivable roads, one-way, with the circuit's name

#### Scenario: Unnamed pieces
- **WHEN** a raceway piece has no `name` but lies inside a facility named "Canadian Tire Motorsport Park"
- **THEN** its edge carries `circuit` "Canadian Tire Motorsport Park"

#### Scenario: An empty track
- **WHEN** the player drives the circuit
- **THEN** no traffic car, parked car or pedestrian is on it

### Requirement: Laps From Raceways
For each closed loop of raceway pieces, chained end to end in their one-way direction, the importer SHALL write a lap to `lap.v0.json`. The start line SHALL be at a mapped timing or start-finish node when there is one, else at the loop's point nearest the pit lane's exit. The lap's `loop_names` SHALL list every name on the loop (the circuit's and each section's).

#### Scenario: A lap at Calabogie
- **WHEN** the player drives the circuit and crosses the start line twice in its direction
- **THEN** the HUD shows the lap time and keeps the best of the session

#### Scenario: Sections with their own names
- **WHEN** a loop is made of pieces named "Hohe Acht", "Sprintstrecke" and others
- **THEN** the lap readout stays visible on every one of them

### Requirement: Track Showroom
Each track pack SHALL name one showroom lot, the largest mapped parking lot inside the facility, in `showroom.v0.json`. The game SHALL fill a showroom lot with every vehicle in the catalogue once, in catalogue order and including vehicles added by packs, at every hour, without occupancy or the per-chunk parked-car cap removing any. A car taken from it SHALL return to its stall once the player is more than 100 m from the stall. A game or pack without the file SHALL fill lots as before.

#### Scenario: Every car at Calabogie
- **WHEN** the player walks into the Calabogie paddock
- **THEN** every vehicle in the catalogue is parked there, once each

#### Scenario: A new car
- **WHEN** a pack adds a vehicle to the catalogue
- **THEN** it is parked in the showroom on the next load

#### Scenario: Back in its stall
- **WHEN** the player takes the van from the showroom, drives a lap and leaves it on the track
- **THEN** a van is back in the van's stall once the player is 100 m from the stall

### Requirement: Elevation Sources
A region's `dem` SHALL choose the elevation source from a table of sources. Each entry gives the source's URL, licence, credit, and whether it is a surface model (trees and buildings included). The pack manifest SHALL credit the source used. For a surface model, the importer SHALL take a road's ground height from the lowest nearby cell, not an interpolated one.

#### Scenario: Outside Canada
- **WHEN** a region with `dem: copernicus-30` is exported
- **THEN** the pack's terrain comes from Copernicus GLO-30 and its manifest carries the Copernicus credit

#### Scenario: A tree line beside the track
- **WHEN** a surface-model cell next to the road holds treetops 20 m above the ground
- **THEN** the road's height comes from the lower cells, not the treetops

#### Scenario: Outside the source's coverage
- **WHEN** the chosen source has no data for the region
- **THEN** the export fails with a message naming the source and suggesting another
