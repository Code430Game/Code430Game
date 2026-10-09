# Change: Houses that look like houses, with yards

**Status: proposed 2026-10-09 (human: "Houses, I forget what they look like now, I think very tall and boxy. Maybe a couple different house models that are varied and more accurate. Some front lawns, back yards, fences.").**

## Why
Ottawa's pack has about 5,100 houses (`detached` 2,057, `house` 1,816, `terrace` 1,199,
`semidetached_house` 37). Today each is its OSM footprint extruded to a height, with a low
hipped or gabled roof and a regular grid of windows. They read as wide boxes: there is no front
door, no porch, no step, no chimney, and the ground around them is the same open lawn as a
park, with no yards or fences. Centretown, the Glebe and Sandy Hill are known for red-brick
houses with porches and steep gables, so the gap shows.

## What Changes
- **House types.** Each house footprint picks a type from its OSM kind, footprint size and shape,
  levels, and a seed:
  - a two-storey detached house with a front gable;
  - a 1.5-storey cottage with a steep roof and a dormer;
  - a bungalow with a low hip roof;
  - semi-detached pairs and terrace rows sharing party walls and a continuous roof line, with
    each unit's door and porch repeated.

  Every type gets a front door facing the nearest street, a porch or stoop with steps, window
  frames, sills and lintels as real geometry (not only facade texture), and a chimney on some.
  Heights come from levels where tagged, else from the type: a two-storey house is about 7 m
  to the eaves, not the tall box it is now.
- **Materials.** A small palette per area: Ottawa red and buff brick, painted clapboard, stone
  trim, picked by seed and tagged `building:material` / `building:colour` where present, so a
  street varies without clashing.
- **Yards.** The land around each house is split by its nearest street: a **front lawn**
  between the facade and the sidewalk (grass, a path to the door, sometimes a low hedge or
  shrubs), and a **backyard** behind it, bounded by a **wood fence** along the shared lines
  with neighbouring backyards (where the gap between neighbours is more than 1.5 m, and never
  across a driveway, path or road). Corner lots get a side yard. The importer computes yard
  polygons and fence lines from footprints, the street graph and landuse; the game draws them.
- **LODs and cost.** Detail geometry (porches, frames, fences) is LOD0 only; LOD1 keeps
  today's simple boxes with the new roof shapes. Fences are one MultiMesh per chunk.
- **Not in this change:** interiors, garden furniture, pools, garages beside houses (they
  stay as their own small buildings), tone-specific variants (a later pass can weather houses
  in gritty and dystopia).

## Impact
- Affected specs: `map-buildings` (ADDED: House Types; ADDED: Yards And Fences).
- Affected code: `tools/osm_import/buildings.py` (house type hints, door side from the street),
  a new `tools/osm_import/yards.py` (yard polygons, fence lines) and `yards.v0.json` with a
  schema; `game/world/buildings/building_builder.gd` (house types), a new
  `game/world/buildings/house_parts.gd` (porch, door, frames, chimney), a yard and fence builder
  in `game/world/dressing/`; golden fixture; Ottawa pack re-exported.
- Performance: the Deck budget decides the LOD0 detail distance; benchmark on a dense street
  (the Glebe) against main.
- Builds on `add-building-variety` (archived) and the street dressing. Overlaps
  `add-skywalks-and-building-parts` in `building_builder.gd`; land one before the other.
