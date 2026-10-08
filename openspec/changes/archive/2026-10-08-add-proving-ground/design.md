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

## The loop: a figure eight from the sketch (second pass, 2026-10-08)
- Two straights at right angles. The highway (`motorway`, one-way pair, 100 km/h, at grade)
  runs west to east along the river's north bank, 25 m north of the flatten margin so the
  bank stays a bank. The vertical road crosses it and the river on one bridge at the map
  centre (`bridge=yes`, `layer=1`, about 90 m of deck with piers on both banks and between
  the highway and the water); a footbridge beside it.
- Top lobe, street level: from the crossing the vertical road runs north as `secondary`,
  `lanes=2`, `oneway=no`, 50 km/h, turns west along the top of the main city, drops into a
  `junction=roundabout` of 14 m radius on the west side where it meets the city's main
  avenue, and comes back east along the highway line to the crossing (that stretch is the
  transition from street to motorway, with the merge and a gore). Avenues cross the lobe at
  signals, streets at stops; junctions only on its straights.
- Bottom lobe, motorway: from the crossing east along the river to the far right, a second
  river bridge heading south, an elevated sweep (`bridge=yes`, `layer=1` where it runs over
  residential streets) round the lower right and back north up the vertical straight. No
  junctions except the `motorway_link` pairs with gores: on the river highway between the
  crossing and the far-right bridge, into the city top right; on the far-right descent, into
  the residential east; and on the vertical ascent, aimed west into the residential west.
  With the roundabout top left that is one way on and off per quarter.
- Lap direction: top lobe clockwise, bottom lobe anticlockwise; the start line sits on the
  vertical straight just north of the centre bridge. The timer is a `lap.v0.json` entry: a
  point on the loop and a direction; it triggers on the car crossing the line in that
  direction, with a 10 s re-arm so a reverse does not count.
- Edge streets end in a U-turn arc back into the grid (two parallel streets joined by a
  semicircle); one street at the east edge is a real dead end for the edge closure.
- The generator keeps the straights, lobes, grids, river and greenbelt as separate pieces with
  their own parameters so a layout change is a parameter change.

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
