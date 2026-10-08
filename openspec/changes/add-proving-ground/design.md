# Design: the proving ground

## Generated, then imported
- The generator writes what Overpass would have returned, nothing more: `osm.json` with
  nodes, ways and tags for roads, paths, bus lanes, rail and the service and parking
  polygons; `buildings.json`, `water.json`, `parking.json`, `services.json` and
  `vegetation.json` in the shapes their importer stages read. The importer is not taught
  anything about the proving ground; it only gains two `--*-json` inputs it lacks.
- Layout is authored in local metres on a fixed base latitude and longitude (the test
  helper's `ll()`), so the region bbox is a plain rectangle around it and the projection is
  the real one (UTM 18N). Coordinates in the backlog style (x, z) work here too.
- The elevation is `SyntheticSource` seeded by the generator (gentle hills, a dip for the
  canal and a rise for the bridge approaches) so the grade pass, the bridge heights, the
  underpass dig and the terrain flattening are all exercised; `FlatSource` is the escape hatch.
- Determinism: the generator takes no clock or random input; the pack diff in CI is the test.

## The loop: a figure eight from the sketch
- Small lobe: `secondary`, `lanes=2`, `oneway=no`, 50 km/h, a teardrop of about 1.1 km
  through the main city, with a `junction=roundabout` of 14 m radius on its west side where
  it meets the city's main avenue. Avenues cross it at signals, streets at stops; junctions
  only on its straights.
- Big lobe: `motorway`, `lanes=2` each way as a one-way pair, 100 km/h, about 1.6 km,
  elevated (`bridge=yes`, `layer=1`) from the crossing round the lower right and back; no
  junctions except the two `motorway_link` exits in the lower right (one each direction),
  each with a gore. It crosses the river once on its east side on its own deck.
- The crossing: both straights pass over the river at the map centre; the street-level
  straight is `bridge=yes layer=1`, the highway straight `bridge=yes layer=2`, the river
  and a footbridge (`layer=1`) beneath. The bridge stage groups the decks; piers land on the
  banks and on the island between the spans.
- Lap direction: clockwise on the small lobe, which makes the big lobe anticlockwise; the
  start line is on the small lobe's north straight. The timer is a `lap.v0.json` entry: a
  point on the loop and a direction; it triggers on the car crossing the line in that
  direction, with a 10 s re-arm so a reverse does not count.
- Edge streets end in a U-turn arc back into the grid (two parallel streets joined by a
  semicircle), the sketch's "turn back" loops; one street at the east edge is a real dead end
  for the edge closure.
- The generator keeps the lobes, grids, river and greenbelt as separate pieces with their own
  parameters so a layout change is a parameter change.

## One of everything (checklist the tests assert)
signals, stop signs, one-way pair, bus-only lane, bus stops, bus loop, sidewalks, crossings,
cycleway, steps, underpass, bridge with sidewalks, footbridge, ramps with gores, shoulders,
roundabout (one, at the bus loop), dead end at the edge, parking lot with aisles, kerb bays,
multi-storey garage with an underground entrance, driveways, houses, apartments, shopfronts,
police with helipad, hospital with ambulance bay, fire station, park with trees and a tree
row, water with a bank, a rail stub with a station. The test lists each OSM feature and the
pack output it must produce (an edge, a polygon, a service entry, a tree count).

## Picking the pack
- `--pack=code430.proving-ground` on the command line, else `Settings.map_pack`, else the
  Ottawa id. The pause menu does not get a pack picker here; `add-pack-loader` owns that.
- `deck-bench.sh --pack <id> --route loop` passes `--pack` and `--spawn` on the start line,
  with `--autodrive` holding the throttle round the loop.

## Decisions for the human
- (decided 2026-10-08) The figure eight from the human's sketch replaces the ring-and-grid
  layout; see above.
- The town's name and street names (the track and gang are "Double Cross"; the town is open).
- Where the gang's turf block sits in the residential south.
- Commit the generated pack (proposed, so a change's diff shows what it did to the district)
  or generate it at build time and commit only the generator.
- The lap timer in this change (proposed, it is small) or later with a race mode.
