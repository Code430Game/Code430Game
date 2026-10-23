## ADDED Requirements
### Requirement: Race Tracks
The importer SHALL import `highway=raceway` ways as drivable roads with their own defaults: three lanes, one-way unless tagged otherwise, a speed of 200 km/h, the OSM `width` when tagged, and a `max_grade` of 0.20. A motorsport facility is a named `leisure=sports_centre` or `leisure=track` area, or any other named area tagged `sport=motor`. The importer SHALL give every raceway edge whose midpoint lies inside a facility that facility's name as its `circuit`, the smallest such facility's when there are several, and SHALL give a raceway edge without a `name` that `circuit` as its `name`. The game SHALL spawn no traffic, parked cars or pedestrians on a raceway, and SHALL build no sidewalks, lane markings or street furniture on one.

#### Scenario: Calabogie imported
- **WHEN** the Calabogie region is exported
- **THEN** the 4,994 m circuit loop and its pit lane are drivable roads, one-way, with the circuit's name

#### Scenario: Unnamed pieces
- **WHEN** a raceway piece has no `name` but lies inside a facility named "Canadian Tire Motorsport Park"
- **THEN** its edge carries `circuit` and `name` "Canadian Tire Motorsport Park"

#### Scenario: An empty track
- **WHEN** the player drives the circuit
- **THEN** no traffic car, parked car or pedestrian is on it

### Requirement: Laps From Raceways
For each closed loop of raceway pieces, chained end to end in their one-way direction, the importer SHALL write a lap to `lap.v0.json`. The start line SHALL be at a mapped timing or start-finish node when there is one, else at the loop's point nearest the pit lane's exit, else at the middle of the loop's longest straight segment. The lap's `loop_names` SHALL list every edge `name` on the loop.

#### Scenario: A lap at Calabogie
- **WHEN** the player drives the circuit and crosses the start line twice in its direction
- **THEN** the HUD shows the lap time and keeps the best of the session

#### Scenario: No pit lane
- **WHEN** a closed raceway loop has no mapped start line and no pit lane
- **THEN** its lap starts at the middle of its longest straight segment

#### Scenario: An unnamed piece
- **WHEN** the player drives a raceway piece that had no `name` in OSM
- **THEN** the lap readout stays visible and a crossing on that piece counts

#### Scenario: Sections with their own names
- **WHEN** a loop is made of pieces named "Hohe Acht", "Sprintstrecke" and others
- **THEN** the lap readout stays visible on every one of them

### Requirement: Track Showroom
Each track pack SHALL list its showroom lots in `showroom.v0.json`: the `amenity=parking` lots whose centroid lies inside the facility, largest area first, ties broken by the lower OSM id. The game SHALL fill the showroom with every vehicle in the catalogue once, in catalogue order and including vehicles added by packs, filling each lot's stalls in turn in the listed order, at every hour, without occupancy or the per-chunk parked-car cap removing any. When the catalogue has more vehicles than the showroom has stalls, the game SHALL leave out the last ones in catalogue order and warn, naming them; the export's validation report SHALL give the showroom's stalls against the base catalogue's vehicles. A car taken from it SHALL return to its stall once the player is more than 100 m from the stall. A game or pack without the file SHALL fill lots as before.

#### Scenario: Every car at Calabogie
- **WHEN** the player walks into the Calabogie paddock
- **THEN** every vehicle in the catalogue is parked there, once each

#### Scenario: A new car
- **WHEN** a pack adds a vehicle to the catalogue
- **THEN** it is parked in the showroom the next time the pack loads

#### Scenario: More cars than stalls
- **WHEN** the catalogue holds more vehicles than the showroom's lots have stalls
- **THEN** the lots are full in catalogue order and the game warns, naming the vehicles left out

#### Scenario: Back in its stall
- **WHEN** the player takes the van from the showroom, drives a lap and leaves it on the track
- **THEN** a van is back in the van's stall once the player is 100 m from the stall

### Requirement: Elevation Sources
A region's `dem` SHALL choose the elevation source from a table of sources. Each entry gives the source's URL, licence, credit, and whether it is a surface model (trees and buildings included). The modes `synthetic`, `flat` and `none` SHALL remain, outside the table. The pack manifest SHALL carry the licence and credit of the source used. For a surface model, the importer SHALL take a road's ground height from the lowest valid source cell under the road's ribbon within 15 m along the road, not an interpolated one, skipping nodata cells and falling back to the nearest valid cell when the window has none.

#### Scenario: Outside Canada
- **WHEN** a region with `dem: copernicus-30` is exported
- **THEN** the pack's terrain comes from Copernicus GLO-30 and its manifest carries the Copernicus credit

#### Scenario: A tree line beside the track
- **WHEN** a surface-model cell next to the road holds treetops 20 m above the ground
- **THEN** the road's height comes from the lower cells, not the treetops

#### Scenario: Outside the source's coverage
- **WHEN** the chosen source has no data for the region
- **THEN** the export fails with a message naming the source and suggesting another
