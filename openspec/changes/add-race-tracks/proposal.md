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
  unnamed, the Nürburgring's pieces are named by section. A raceway inside a named facility
  outline (a named `leisure=sports_centre` or `leisure=track` area, or any named area with `sport=motor`) gets
  the facility's name as `circuit` on the edge. Its own `name` stays the section's.
- **Laps from the map.** For each closed raceway loop (pieces chained end to end by one-way
  direction), the importer writes a lap to `lap.v0.json`.
  - **Start line:** at a node on the loop tagged or named as the start/finish or timing line where
    the map has one. Otherwise, at the loop's point nearest the pit lane's exit.
  - **Readout:** `loop_names` lists the loop's names (the circuit's name and each section's),
    so the readout shows anywhere on the loop. The lap file format does not change.
- **A paddock with every car.** Each track pack has one showroom lot: the largest mapped
  `amenity=parking` inside the facility (Calabogie has two surface lots there). The idea is to
  try any car on the track without a car selector, which would sit outside the game's usual
  play (human, 2026-10-23: "we should include a parking lot with all the cars on these too").
  - It holds every vehicle in the catalogue once, in catalogue order, including vehicles a pack
    adds. A new car shows up here as soon as it's in the catalogue.
  - It's always full, at every hour, with no occupancy draw. The per-chunk parked-car cap
    doesn't drop any of its cars.
  - A car the player takes comes back to its stall once the player is more than 100 m from it,
    so the lineup is never short.
  - The importer names the lot in a new optional file, `showroom.v0.json` (`lots`: lot ids).
    `parking.v0.json` doesn't change, so an older game ignores the file and fills the lot the
    usual way.
  - If the lot has fewer stalls than there are cars, the export's validation report says so.
    The overflow continues in a second lot when there is one.
- **More elevation sources.** A region's `dem` picks the source. The licence and credit go in
  the pack manifest (the existing attribution requirement):
  - `hrdem` (today's NRCan 2 m mosaic);
  - `hrdem-1m` (NRCan's 1 m mosaic, needed for Calabogie);
  - `copernicus-30` (the global Copernicus GLO-30, free with credit). It is a *surface*
    model: trees and buildings are in its heights. Under a road the importer uses the
    lowest nearby cell, not the average, so a tree line doesn't lift the track;
  - more later, per country (USGS 3DEP for the US, the German states' 1 m models). Each is
    one entry in a table: URL pattern, licence, credit, and whether it is a surface model.
- **Track packs.** Each circuit is its own pack (not a district set), chosen in the Packs tab
  like the proving ground. Calabogie goes first, in a new pack repo
  `Code430Packs/Location-CalabogieOnCa`, made from PackTemplate. Its border is the
  facility's outline plus 200 m.
- **Second phase (separate tasks, same change):** the Nürburgring GP circuit with
  `copernicus-30`, and the Nordschleife if a 20.8 km loop loads on the Deck. Its area is
  about 7 × 5 km, mostly forest, so the Deck load time and memory decide.
- **Not in this change** (listed as later todos in `tasks.md` section 4):
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
  - `tools/osm_import/`: `showroom.v0.json` from the facility's largest lot;
    `docs/pack-format/showroom.schema.v0.json` (new), checked by the pack validator;
  - `game/world/dressing/parked_cars.gd`: showroom lots filled with the whole catalogue,
    exempt from occupancy and the chunk cap, and taken cars returned to their stalls;
  - `game/`: otherwise no new code expected. Traffic, parking and pedestrians already read the
    class lists. To check: speed-limit signs and the HUD's road name on a raceway;
  - tests on both sides; a raceway loop on the proving ground is not needed (its ring already
    tests laps).
- New pack repo `Location-CalabogieOnCa`; `packs.lock.json` gains it once its release passes.
- Deck benchmark on Calabogie, and later the Nürburgring.
