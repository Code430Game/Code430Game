# Change: Underground parking (one tier)

**Status: proposed 2026-10-05 (human: "I also wonder do we see the subterranean parking? I am debating if we create a simple one tier for those. Say under the NAC and under the museum of natural sciences by the queensway start position.")**

## Why
The game skips underground and multi-storey lots (`parking_lot_builder.gd`), so the city's
garages don't exist. Their driveways end at a wall of terrain, which accounts for some of the
backlog's "terrain shows through at junctions" cases: n14141327481 (+10.5 m) sits beside
garage entrances 14141327480, 14141327487 and 14141327491. Mappers rarely draw garage
outlines in Ottawa: the pack has one underground lot with an outline (capacity 250, at
634, −860). They do map entrances. The cached OSM has 109 `amenity=parking_entrance` or
underground `amenity=parking` points, and 105 of them sit on a road-graph node at the end of
a driveway. Among them:
- three "NAC underground parking" entrances (capacity 200) around the National Arts Centre
  (building at 123, −353)
- an entrance at (547, 828) beside the Victoria Memorial Museum Building (the Canadian
  Museum of Nature, 489, 808)
- the YMCA garage (475, 1005) near the start position

## What Changes
Two tiers, from the human's follow-up ("make a closed door at the ends of the roads to the
underground items or just put small lots inside"):
- **Door tier (every entrance).** The driveway ends in a short ramp down to a closed garage
  door set in a concrete portal. It costs little and fixes every driveway that ends in a
  terrain wall today. Private and unnamed garages stay at this tier.
- **Garage tier (public garages).** Garages with a name, a capacity, `access=yes|customers|
  permissive`, or a fee, plus any named in `garage_overrides` (the NAC and the Museum of
  Nature), get an open entrance and the one-level lot below.

- **Garages from entrances (importer).**
  - Cluster entrance points that share a name or are within `garage_merge_m` of each other.
  - Take the footprint from an underground lot outline when there is one. Otherwise use the
    building the entrances serve: the nearest building whose footprint is within
    `garage_building_m` of an entrance, shrunk by 2 m. Otherwise use a rectangle sized from
    the capacity (or a default) behind the entrance.
  - Each garage gets one level, `garage_depth_m` (3.2 m) below the entrance's street, and a
    ramp from each entrance down to that level.
  - Export them in `parking.v0.json` as `kind: "underground"` with `levels: 1`, `tier` (`door`
    or `garage`), the entrances, the floor height and the ramps.
- **Door portal (game).** A ramp of about 6 m from the driveway node down to a roll-up door in
  a concrete portal, with collision. The terrain hole is only as big as the ramp.
- **The garage (game, garage tier).**
  - A concrete box under the footprint: floor, ceiling and walls.
  - Columns on an 8 m grid.
  - Stalls laid out by the existing stall builder on the floor polygon, with drive aisles
    between rows.
  - Ceiling light strips (emissive, plus a few `OmniLight3D` on `high`).
  - The ramp cut uses the underpass machinery from `add-underpasses`: terrain holes, ramp
    floor and walls.
  - Built at the NEAR tier only, and part of collision.
- **Parked cars.** Garage stalls use `ParkedCars` (deterministic per hour, takeable).
  Occupancy comes from a new `garage` row in `parking_config.json`: full by day for
  commercial and venue garages, and for residential garages at night.
- **Wayfinding.** Garages show on the maps as a "P" with a dashed outline, and the minimap
  shows the floor while the player is inside.
- **Not in this change:** more than one level (the `levels` field allows it later),
  multi-storey above-ground garages (the next tier of this work), barriers or fees at the
  entrance, interiors connecting to buildings, and pedestrian stairs.

## Co-op authority
Static world from the pack. Garage parked cars follow the parked-car rules (host-authoritative takes, mirrored stalls).

## Impact
- Affected specs: `parking` (ADDED: Underground Garages).
- Affected code: `tools/osm_import/parking.py` (entrance clustering, footprints, ramps;
  schema), `game/world/dressing/parking_lot_builder.gd` (garage box, columns, lights, stalls),
  `game/world/roads/underpass_builder.gd` (ramps reused), `parked_cars.gd` (garage occupancy),
  map renderers, and the Ottawa pack (re-exported).
- Performance: one box and a few hundred stalls per garage, near tier only. Deck benchmark
  against main.
