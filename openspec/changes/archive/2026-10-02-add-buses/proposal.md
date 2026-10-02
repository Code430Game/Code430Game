# Change: Buses on bus lanes

**Status: proposed 2026-10-02 (human asked about the bus lanes on Rideau and whether the other cars could be real vehicles).**

## Why
Ottawa's downtown runs on buses: the Transitway, Lyon Street's bus-only block, the reserved
lane on Waller. The import had none of it (bus-only streets were dropped as `access=no`),
and traffic was all cars. Buses give the big streets their real texture and the player
something large to drive around.

## What Changes
- **Importer:** bus-only ways (`access=no` with `bus`/`psv` yes or designated, `highway=busway`)
  are kept and marked `bus: "only"`; `bus:lanes`, `busway=lane` and `lanes:bus` mark one
  forward lane as `bus: "lane"` with its index. Bus stop positions (`public_transport=stop_position`
  with `bus=yes`, `highway=bus_stop`) on drivable ways export as `bus_stops`.
- **Lanes:** reserved lanes are `bus_only`; cars never choose them, buses prefer them and
  otherwise keep to the bigger roads. Reserved lanes are painted a red strip.
- **Buses:** a share of traffic spawns as buses (city bus mesh, 11.5 m, own MultiMesh, bus
  colours), with following distances by vehicle length and bus-sized physics bodies. They
  slow for stops on their lane, stand six seconds, and carry on. Buses cannot be taken by the
  player. Snapshots carry the kind for co-op.
- **Not in this change:** routes and timetables, passengers boarding, bus shelters.

## Impact
- Affected specs: `traffic` (new requirement).
- Affected code: `filter.py`, `graph.py`, `export.py`, schema; `road_graph.gd`,
  `lane_graph.gd`, `marking_builder.gd`, `bus_mesh.gd` (new), `traffic_agent.gd`,
  `traffic_manager.gd`, `traffic_car.gd`, `traffic_config.json`, tests; Ottawa pack re-exported.
- Performance: one more MultiMesh; agent count unchanged. Deck measured.
