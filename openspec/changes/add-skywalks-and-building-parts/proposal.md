# Change: Skywalks, footbridges and raised building parts

**Status: proposed 2026-10-02 (human, after a Deck drive: "a walkway, a connector between buildings, more than a car height above the roadway").**

## Why
Downtown Ottawa and Hull are stitched together above street level: Place du Portage and
Place du Centre bridge Boulevard Maisonneuve, the National Arts Centre sits over Lawrence
Freiman Lane, footbridges cross the canal and the Transitway, and the big complexes carry
raised building parts. The import flattens all of it. Pedestrian ways drop their `bridge` and
`layer` tags (`tools/osm_import/graph.py` `PedestrianWay` has neither), so about 60 footbridges
in the extract are drawn at ground level across the roads or water they cross. Buildings ignore
`min_height` and `building:min_level` (`tools/osm_import/buildings.py`), so about 90 raised
parts become solid blocks from the ground, and the one `building=bridge` is a block too.
Separately, a building whose footprint spans a sunken road gets one median ground height and
floats over the road with no underside: Place du Centre is 10.8 m above Maisonneuve, the NAC
9.1 m above Freiman Lane. That floating block is what the human saw.

## What Changes
- **Importer, pedestrian ways:** keep `bridge`, `layer` and `covered` on pedestrian ways; a
  footbridge takes its height from the road-bridge rule (deck height over what it crosses,
  approach ramps to the ground ways at each end) instead of the terrain; `apply_pedestrian_elevation`
  and `split_pedestrian_under_bridges` treat them like road bridges.
- **Importer, buildings:** export `min_height_m` (from `min_height`, else `building:min_level`
  times the storey height, else 0) and a `bridge` flag for `building=bridge`. A footprint that
  spans a drivable road with the road more than a threshold below the median ground gets
  `spans_road: true` and a `clearance_y` equal to the road height plus a clearance.
- **Game, buildings:** walls start at `ground_y + min_height_m`; a raised part gets an underside
  face so it reads as a bridge or overhang, not a floating slab. A building that spans a road
  keeps its roof but the walls above the road stop at `clearance_y` with an underside, so the
  road passes through a covered opening with collision above head height. Chunking and LODs
  unchanged.
- **Game, dressing:** footbridges are ribbons with a deck, parapets and the sidewalk material,
  with collision, chunked like sidewalks; covered ones get a roof strip. Steps at their ends
  stay as they are.
- **Not in this change:** indoor corridors, the Rideau Centre interior, moving bridges opening,
  escalators, people using the skywalks on purpose (pedestrians already walk any footway).

## Co-op authority
Static geometry, nothing replicated.

## Tone
Not content; no descriptors.

## Impact
- Affected specs: `map-buildings` (Building Footprints In Map Packs and Extruded Buildings
  modified), `street-dressing` (new requirement).
- Affected code: `tools/osm_import/graph.py`, `filter.py`, `elevation.py`, `buildings.py`,
  `export.py`, schemas `road_graph.schema.v0.json` and `buildings.schema.v0.json` (additive
  fields), golden files, `tools/tests/test_osm_buildings.py`, `test_osm_elevation.py`;
  `game/world/buildings/building_builder.gd`, `game/world/roads/sidewalk_builder.gd` or a new
  `footbridge_builder.gd`, tests; Ottawa pack re-exported.
- Performance: a few hundred extra quads; Deck measured at Place du Portage and the NAC.
