# Change: Race tracks from OpenStreetMap, with laps

**Status: proposed 2026-10-23 (human: "can you check if calabogie is mapped in open street
maps?", then: "maybe we pull and do a proposal for this race track. I wonder if we do a
couple, calabogie is local but there should be others, Nürburgring, ... would we need to keep
this in Canada for the elevation data?")**

## Why
Real circuits are well mapped in OpenStreetMap as `highway=raceway`, and the game can already
time laps (the proving ground's `lap.v0.json`). A circuit is a small map with one long, fast,
hilly road. It shows off the driving, and players can compare lap times. Checked 2026-10-23:

| Circuit | OSM | Elevation |
|---|---|---|
| Calabogie Motorsports Park, ON | one closed loop (way 279357480, 4,994 m, one-way), pit lane, connectors, the facility outline | NRCan HRDEM **1 m** mosaic covers it; the 2 m mosaic the importer uses today does not |
| Canadian Tire Motorsport Park (Mosport), ON | 21 raceway ways: two closed loops plus named straights | HRDEM (to confirm) |
| Circuit Gilles-Villeneuve, Montréal | one closed loop (4,362 m) and the pit lane | HRDEM (to confirm) |
| Nürburgring, Germany | 98 raceway ways, split into named sections (Hohe Acht, Sprintstrecke, ...) | Copernicus GLO-30 has it; Rhineland-Palatinate's 1 m bare-earth model (to confirm) |
| Laguna Seca, California | 9 raceway ways, named in pieces, and the pit lane | USGS 3DEP 1 m (public domain) |

Elevation does not tie us to Canada. The importer reads one DEM (HRDEM 2 m) today, but every
region file already names its `dem`, and the reader is a windowed read of a cloud-optimized
GeoTIFF that works for any such source.

## What Changes
- **Raceways are roads.** `highway=raceway` joins the drivable classes. Its defaults are 3
  lanes (one-way unless tagged otherwise), 200 km/h, and the OSM `width` when tagged. Its
  `max_grade` is 0.20, so the track's hills stay: the Nordschleife has stretches of about 17%.
  - No traffic, parked cars or pedestrians spawn on it.
  - It gets no sidewalks, lane markings or street furniture.
  - Junctions with the pit lane and service roads are built like any other junction.
- **Every piece of a circuit is named.** OSM splits a circuit into pieces: CTMP's loop is
  unnamed, the Nürburgring's pieces are named by section. A facility is a named `leisure=sports_centre` or `leisure=track` area, or any other named area tagged `sport=motor`.
  A raceway edge whose midpoint lies inside a facility gets the facility's name as `circuit`;
  inside two, the smaller one's. A piece with its own `name` keeps it (the section's); an
  unnamed piece also takes the facility's name as its `name`, because the lap timer finds
  the loop by edge `name`.
- **Laps from the map.** For each closed raceway loop (pieces chained end to end by one-way
  direction), the importer writes a lap to `lap.v0.json`.
  - **Start line:** at a node on the loop tagged or named as the start/finish or timing line where
    the map has one. Otherwise, at the loop's point nearest the pit lane's exit. A loop with
    neither gets its start line at the middle of its longest straight segment, where a real
    start line usually is.
  - **Readout:** `loop_names` lists every edge `name` on the loop (each section's, and the
    circuit's on the pieces that took it), so the readout shows anywhere on the loop. The lap
    file format and the lap timer do not change.
- **A paddock with every car.** Each track pack has a showroom: the mapped `amenity=parking`
  lots whose centroid is inside the facility (Calabogie has two surface lots there), largest
  first, ties broken by the lower OSM id. The idea is to
  try any car on the track without a car selector, which would sit outside the game's usual
  play (human, 2026-10-23: "we should include a parking lot with all the cars on these too").
  - It holds every vehicle in the catalogue once, in catalogue order, including vehicles a pack
    adds. The cars fill the first lot's stalls, then the next lot's, in that order. A car added
    to the catalogue is there the next time the pack loads.
  - It's always full, at every hour, with no occupancy draw. The per-chunk parked-car cap
    doesn't drop any of its cars.
  - A car the player takes comes back to its stall once the player is more than 100 m from it,
    so the lineup is never short.
  - The importer lists the lots, in that order, in a new optional file, `showroom.v0.json`
    (`lots`: lot ids). `parking.v0.json` doesn't change, so an older game ignores the file and
    fills the lots the usual way.
  - **Not enough stalls.** The export's validation report gives the showroom's stalls against
    the base catalogue's cars. If the catalogue outgrows the stalls at load (pack vehicles),
    the cars that don't fit are left out, the last in catalogue order first, with a warning
    naming them.
- **More elevation sources.** A region's `dem` picks the source. The source's licence and
  credit both go in the pack manifest (the existing attribution requirement asks for the
  credit). `synthetic`, `flat` and `none` stay as they are (tests and debugging); they download
  nothing and are not in the table.
  - `hrdem` (today's NRCan 2 m mosaic, unchanged and still the default);
  - `hrdem-1m` (NRCan's 1 m mosaic, needed for Calabogie);
  - `copernicus-30` (the global Copernicus GLO-30, free with credit). It is a *surface*
    model: trees and buildings are in its heights. Under a road the importer takes the
    lowest valid cell under the road's ribbon within 15 m along the road, not an
    interpolated height, so a tree line doesn't lift the track. On a slope this reads low by
    at most the grade times 15 m (3 m at 20%), which the grade limiter then smooths. Nodata
    cells are skipped; with none valid in the window, the nearest valid cell is used, as the
    importer does today;
  - more later, per country (USGS 3DEP for the US, the German states' 1 m models). Each is
    one entry in a table: URL pattern, licence, credit, and whether it is a surface model.
    A source is added to the table only once its licence is checked to allow redistribution
    in a pack.
  - Every source fails an export it has no data for, naming the source and suggesting
    another (as `hrdem` does today).
- **Track packs.** Each circuit is its own pack (not a district set), chosen in the Packs tab
  like the proving ground. Calabogie goes first, in a new pack repo
  `Code430Packs/Location-CalabogieOnCa`, made from PackTemplate. Its border is the
  facility's outline plus 200 m.
- **Second phase (separate tasks, same change):** the Nürburgring GP circuit with
  `copernicus-30` (a German state's 1 m model only once it is in the table), and the
  Nordschleife if a 20.8 km loop loads on the Deck. Its area is about 7 × 5 km, mostly
  forest. The Deck benchmark gives its load time, memory and frame time, and the human
  decides from those whether it goes in.
- **Not in this change** (listed as later todos in `tasks.md` section 5):
  - kerbs, gravel traps, tyre walls, grandstands and pit buildings beyond what OSM's
    building outlines already give;
  - AI racers, a race mode, a lap leaderboard across players;
  - racing lines.

## Impact
- Affected specs: `specs/road-network/spec.md` (ADDED: Race Tracks, Laps From Raceways, Track Showroom,
  Elevation Sources).
- Affected code:
  - `tools/osm_import/road_classes.json`: `raceway` in `drivable_classes`, its defaults, and
    the no-traffic / no-sidewalk lists;
  - `tools/osm_import/`: a new `circuits.py` (facility names, loops, start lines, the lap
    file); `elevation.py` (a source table, `hrdem-1m`, `copernicus-30` with lowest-cell sampling
    under roads); `__main__.py` (`--dem` choices from the table);
  - `tools/osm_import/`: `showroom.v0.json` listing the facility's showroom lots in order;
    `docs/pack-format/showroom.schema.v0.json` (new), checked by the pack validator;
  - `game/world/dressing/parked_cars.gd`: showroom lots filled with the whole catalogue,
    exempt from occupancy and the chunk cap, and taken cars returned to their stalls;
  - `game/`: otherwise no new code expected. Traffic, parking and pedestrians already read the
    class lists. To check: speed-limit signs and the HUD's road name on a raceway;
  - tests on both sides; a raceway loop on the proving ground is not needed (its ring already
    tests laps).
- New pack repo `Location-CalabogieOnCa`; `packs.lock.json` gains it once its release passes.
- Deck benchmark on Calabogie, and later the Nürburgring.
