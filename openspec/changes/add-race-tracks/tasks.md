## 1. Importer
- [ ] 1.1 `road_classes.json`: `raceway` drivable (3 lanes, one-way unless tagged, 200 km/h, OSM `width` when tagged, `max_grade` 0.20); no traffic, parking, pedestrians, sidewalks, lane markings or street furniture on it; tests
- [ ] 1.2 `circuits.py`: the facility's name as `circuit` on raceways inside it; closed loops chained from one-way pieces; a start line at a mapped timing/start-finish node, else nearest the pit lane exit; `lap.v0.json` with the loop's names; tests (a synthetic loop split into named and unnamed pieces)
- [ ] 1.3 `elevation.py`: a DEM source table (URL, licence, credit, surface or bare earth); `hrdem-1m` and `copernicus-30`; lowest-cell sampling under roads for surface models; `--dem` choices from the table; the credit in the manifest; tests
- [ ] 1.4 Showroom: the facility's largest `amenity=parking` named in `showroom.v0.json`; `docs/pack-format/showroom.schema.v0.json` checked by the pack validator; a report line when the lot has fewer stalls than the catalogue has cars (overflow into a second lot); tests
## 2. Game
- [ ] 2.1 `parked_cars.gd`: a showroom lot holds every catalogue vehicle once in catalogue order (pack vehicles too), always full, exempt from occupancy and the chunk cap; a taken car returns to its stall once the player is 100 m away; a pack without the file fills its lots as before; tests
## 3. Calabogie
- [ ] 3.1 Pack repo `Code430Packs/Location-CalabogieOnCa` from PackTemplate; `regions/calabogie.json` (facility outline plus 200 m, `dem: hrdem-1m`); a release built and checked locally before it is locked
- [ ] 3.2 Screenshots: the start line, the lap readout, two of the track's hills
- [ ] 3.3 Deck benchmark on Calabogie
- [ ] 3.4 **Stop: the human drives laps at Calabogie on the Deck**
## 4. Nürburgring (second phase)
- [ ] 4.1 `regions/nurburgring-gp.json` with `copernicus-30` (or a German state's 1 m model, if its licence allows redistribution), in a `Location-NurburgDe` pack repo; screenshots against photos of the same corners
- [ ] 4.2 The Nordschleife only if its Deck load time and memory are acceptable; else noted here and left out
- [ ] 4.3 **Stop: the human drives the Nürburgring on the Deck**
## 5. Later (follow-up changes, not this one; human, 2026-10-23: "put kerbs and gravel traps as later todos so we remember"). They do not block archiving: before archiving, each becomes its own proposal or stays on the backlog
- [ ] 5.1 Kerbs: the red and white kerbs on the apexes and exits (OSM rarely maps them; from the track's curvature, or mapped `barrier=kerb` where present), with a rumble the car feels
- [ ] 5.2 Gravel traps: run-off areas outside the corners (OSM `surface=gravel` areas where mapped), with grip and drag that slow a car that runs wide
- [ ] 5.3 Tyre walls, grandstands and pit buildings beyond OSM's building outlines
- [ ] 5.4 AI racers or a race mode; a lap leaderboard across players
