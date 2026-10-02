# Change: Parking lots, aisles and parked cars

**Status: proposed 2026-10-02 (human: "we should also add parking lots to the specs"). This revisits the 2026-09-30 decision to keep parking aisles and driveways out of the road graph (follow-up 8.1 in the archived `add-osm-road-import`); the human asked for lots, and lots are not drivable without their aisles.**

## Why
The district has 695 `amenity=parking` features in the extract (662 surface lots, 12
multi-storey, 11 street-side, 1 underground) and the importer draws none of them: the
polygons are not fetched, and `service=parking_aisle` and `service=driveway` ways (650 and
595 in the bbox) are dropped by `excluded_service_values` in `road_classes.json`. The result
is blank green between buildings where a city has asphalt and rows of cars, no way to pull
off the street, and the private-road islands the validation report lists stay disconnected.
Parked cars are also the cheapest population a crime game can have: something to take, hide
behind and crash into that never needs a brain.

## What Changes
- **Importer, roads.** `parking_aisle` and `driveway` service ways are kept as edges of a new
  road class `parking` (speed 15 km/h, one lane each way unless `oneway`, width from
  `width` else 5.5 m for aisles and 3.5 m for driveways), connected to the street graph at
  their shared nodes. `drive-through` and `emergency_access` stay dropped. The validation
  report's private-road islands are recounted after the change.
- **Importer, lots.** A new stage `parking.py` fetches `amenity=parking` ways and relations,
  exports `parking.v0.json`: rings (clipped like buildings), `kind` from `parking=*`
  (`surface` default, `street_side`, `multi-storey`, `underground`, `rooftop`), `capacity`,
  `access`, `fee`, `operator`, `orientation` where tagged, `stall_dir` derived from the
  longest aisle inside the ring (else the longest ring edge), `entrances` at nodes where an
  aisle or driveway meets a street edge, ground height from the flattened terrain. Street-side
  bays: `parking:lane:*`, `parking:left|right|both` and their `:orientation` tags (155 ways in
  the bbox) export as `bays` along the kerb side of the edge with their orientation.
- **Lanes.** Edges of class `parking` yield lane paths flagged `parking_only`, like `bus_only`:
  traffic never chooses them (`choose_next` and spawn skip them), the player drives them
  freely. A connector into a parking lane inherits the flag.
- **Game, lots.** `ParkingLotBuilder` under `game/world/dressing/`: surface lots become an
  asphalt slab at ground height with a kerb edge, stall markings laid perpendicular to
  `stall_dir` on both sides of each aisle (90 degree stalls 2.6 m by 5.5 m by default, angled
  when `orientation` says so, parallel for street-side bays), a curb stop per stall, and a
  lot sign at the main entrance showing the operator name as `Label3D` text when the pack
  has one, else a generic "P". Multi-storey lots stay buildings (they already extrude from
  the building import; ramps are later). Underground lots and rooftop lots are not drawn.
- **Game, parked cars.** Stalls are filled at a seeded occupancy per lot (seed from the lot
  id, occupancy by hour: downtown lots fuller by day, residential and street bays fuller at
  night, tunables in `parking_config.json`) with vehicles from the catalogue in
  `add-vehicle-variety` (hatchbacks and sedans weighted up, no buses or trucks), drawn as
  per-chunk MultiMeshes by class and LOD like traffic, with no physics body unless the car is
  among the nearest few to a player, using the traffic body pool rules. `--parking-occupancy=`
  pins the share for screenshots. Taking a parked car follows the traffic rule (interact
  next to it, host only in co-op); the stall stays empty afterwards for the session.
- **Not in this change:** paying for parking, meters and tickets, towing, garage interiors,
  ramps into multi-storey lots, pedestrians walking to and from cars, car alarms, the
  player's car being remembered in a lot between sessions.

## Co-op authority
Parked cars are deterministic host state: seed plus lot id plus hour gives the same set on
every peer, so nothing is sent until a car is taken, when the host sends the stall id and
the taken car joins the traffic snapshot like a taken traffic car. Clients mirror.

## Tone
Not content. Lot signs show operator names as plain text from OSM data; no ads.

## Impact
- Affected specs: `parking` (new), `road-network` (OSM Road Import modified: parking class),
  `traffic` (Parking-Only Lanes added).
- Affected code: `tools/osm_import/road_classes.json` (class `parking`, excluded values
  shrink), `filter.py`, `graph.py`, `parking.py` (new), `fetch.py` (second query like water),
  `export.py`, `pack.py` (terrain flattening under lots), `validation.py` (lot and bay counts,
  islands recount), `docs/pack-format/parking.v0.schema.json` and `road_graph.schema.v0.json`
  (class enum), `tools/pack_tools/validate.py`, tests and golden files;
  `game/world/roads/road_graph.gd` and `lane_graph.gd` (`parking_only`), `traffic_manager.gd`
  (skip parking lanes, body pool shared with parked cars), `game/world/dressing/parking_lot_builder.gd`
  (new), `parked_cars.gd` (new), `parking_config.json` (new), `game/actors/player/player.gd`
  (take a parked car), `game/scenes/play_testbed.gd` (flag), `game/ui/map/map_renderer.gd`
  (lots as a grey fill), tests; Ottawa pack re-exported.
- Performance: parked cars are the cost. Expected in the Ottawa pack: 662 surface lots, about
  9,000 stalls from the tagged capacities scaled to the untagged lots, roughly 4,000 parked
  cars at the daytime occupancy. Per-chunk caps: `deck` 120 parked cars per chunk at LOD0
  within 80 m and LOD1 beyond, `high` 300 and 150 m. Draw calls per chunk at most one per
  catalogue class per LOD. Deck measured in the Market and at a Queensway lot.
