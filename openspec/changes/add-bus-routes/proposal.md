# Change: Bus routes, timetables and shelters

**Status: proposed 2026-10-02 (human asked for a slate of proposals that other agents can pick up in fresh contexts). Follow-up to `add-buses`; implement after it is archived.**

## Why
Buses exist but wander: they pick any bus-capable lane at each junction and stand at any stop
they pass. Real buses run numbered routes on a headway, and the number on the front is how a
city reads them. Routes also give stops a reason to be there and let shelters carry a placard,
which is the next layer of street texture on the big streets.

## What Changes
- **Importer.** The Overpass query also fetches `relation["route"="bus"]` with their members.
  Each relation becomes a route in `road_graph.v0.json` under `bus_routes`: id, `ref` (the
  number), name, colour, the ordered edge ids its ways map to (gaps closed by shortest path over
  bus-capable edges, reported in the validation report) and the ordered stop ids along it.
  Where a bus-lane corridor has no relation covering it (the extract has Lyon Street North, the
  Transitway and Waller Street tagged as lanes), a synthetic route is written along the corridor
  and its connecting big roads, named from the street and marked `synthetic: true`. Bus stops
  gain `name`, `shelter` and `routes`. A per-route `headway_s` defaults from the road class and
  can be overridden in `overrides.json`.
- **Buses on routes.** A bus agent carries a route and a stop index. Lane choice at junctions
  follows the route's next edge; off-route after a hit or a blocked lane, the bus rejoins at the
  nearest route edge ahead or, if none within reach, falls back to today's free roaming. It stops
  only at its route's stops, dwells, and at the terminus turns around (or loops where the relation
  loops). Route buses are placed by time: a route's buses sit at positions given by the host
  clock modulo the headway, so a route looks served the moment a player arrives and in co-op all
  peers agree. The free-roaming share from `add-buses` remains for streets without routes.
- **Destination sign.** The bus mesh gains an emissive sign strip over the windscreen that shows
  the route number from a digit atlas driven by per-instance custom data (three digits), amber
  on black, readable from 40 m.
- **Shelters and flags.** At stops with `shelter=yes` a glass shelter with a roof and a bench
  on the sidewalk side; elsewhere a pole with a flag sign. Both carry a placard listing route
  numbers from a digit atlas. Built in `game/world/dressing/bus_stop_builder.gd` into the
  dressing chunks with collision and LODs.
- **Not in this change:** passengers boarding or alighting, bus interiors, a timetable board
  with times, night routes, the player riding a bus.

## Co-op authority
Routes and placement are host-simulated like all traffic; the route number joins the traffic
snapshot as the custom-data float so mirrored buses on guests show the right sign. Time-based
placement uses the signal clock the host already shares.

## Tone
Route names and numbers are map data with no descriptors; shelters are geometry. The shelter
placard is a surface a later advertising change can hang a billboard ad on, which is where tone
would enter.

## Impact
- Affected specs: `traffic` (modified requirement from `add-buses`), `street-dressing` (new
  requirement).
- Affected code: `tools/osm_import/fetch.py` (relations), `osm_data.py`, `graph.py`,
  `export.py`, `validation.py`, `docs/pack-format/road_graph.schema.v0.json`, Ottawa pack
  re-exported; `game/world/roads/road_graph.gd`, `game/world/traffic/traffic_agent.gd`,
  `traffic_manager.gd`, `traffic_config.json`, `game/actors/vehicles/bus_mesh.gd` and the car
  shader (sign atlas), `game/world/dressing/bus_stop_builder.gd` (new), `game/core/net/world_sync.gd`
  (sign in snapshots), tests in `tools/tests` and `game/tests`.
- Performance: shelters are a few hundred small meshes chunked with the dressing; the sign is
  one more surface on the existing bus MultiMesh. Deck measured on Albert and Slater.
