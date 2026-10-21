# Design: dressing the proving ground

- **Frontage lots, not block fills.** Every axis-aligned street segment is walked on both
  sides; lots are placed along it at a setback from the kerb, so buildings face their street
  and leave the sidewalk, the way the existing houses on Park Road do. Arcs (the bends, the
  roundabout, the sweeps) get nothing, which keeps the loop's corners open.
- **Exclusion is geometric and cheap.** A lot is rejected when any corner or its centre lies
  within a per-class clearance of any other way's segment (motorway 16 m, secondary 11,
  tertiary 10, residential 9, links 10, service 5, paths 4, rail 8), inside the river, the
  greenbelt wood, the bank grass, the park, a bridge area, the turf rectangle, within
  the roundabout's radius plus 12 m, or overlapping an existing building, parking or service
  area (axis-aligned bounding boxes; every footprint here is a rectangle).
- **Zones by position.** South of the river is residential; north of it and west of the
  vertical is the main city; north and east is the city. Each zone has its own lot sizes,
  kinds, storeys and tags; the avenues (tertiary) take the commercial frontages, the streets
  (residential class) take the rest.
- **Seeded variety.** One `random.Random(7)` per zone, consumed in a fixed order, so the pack
  regenerates byte for byte; footprint widths, depths, storeys, semi/terrace choice, shop
  type and tree species come from it.
- **Driveways** only on detached houses, every second one, as a `service=driveway` way from
  the house's front to a vertex inserted on its street; terraces and semis share the kerb.
- **Trees.** Rows are `natural=tree_row` ways 9 m off each avenue's centreline on both sides
  (the importer spaces them 8 m), clipped 15 m short of junctions so signal heads and stop
  lines stay clear. Yard trees are `natural=tree` nodes 6 m behind a detached house. The bank
  road's row sits on its north side; the south side is the riverbank grass.
- **Town name** is a parameter of `build()`; the module constants that carry it (station,
  police, hospital, fire hall) read it at build time.

## Decisions for the human
- The town's name (still "Double Cross", the track and gang's name).
- Tower count near the roundabout (four) and their height (10 to 16 storeys).
- Whether the park should gain a playground or bandstand footprint (not now).
