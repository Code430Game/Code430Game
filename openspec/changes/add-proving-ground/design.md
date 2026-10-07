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

## The loop as a track, the grid inside it
- Ring road class `secondary`, `lanes=2`, `oneway=no`, 50 km/h; the straight along the water
  is 400 m; sweepers are arcs of 180 m and 140 m radius with no junction on them; the chicane
  is two 60 m offsets on the far side from the water.
- The grid sits inside the ring. Its two avenues (`tertiary`) run across the grid and out to
  the ring on both sides, meeting it at four signalled T-junctions; four `residential` streets
  reach the ring at stop signs. So the ring is a lap when driven straight through and the way
  into town when turned off, and every junction type the junction builder handles (signals,
  stops, a T against a curve, a four-way inside the grid) is on the lap or one turn off it.
  Junctions on the ring sit on the straights, never in a sweeper, so laps stay fast.
- The grade-separated crossing is the loop bridging the highway stub (`bridge=yes`,
  `layer=1`); the canal bridge is a second bridge with a footbridge beside it.
- The start line is a `lap.v0.json` entry: a point on the loop and a direction; the timer
  triggers on the car crossing the line in that direction, with a 10 s re-arm so a reverse
  does not count.

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
- Grid inside the ring (proposed, the human's preferred reading) or the ring inside a larger
  grid; the generator keeps the ring and grid as separate pieces so swapping is a layout
  change, not a rewrite.
- The town's name and street names (Harbourline is a placeholder).
- Commit the generated pack (proposed, so a change's diff shows what it did to the district)
  or generate it at build time and commit only the generator.
- The lap timer in this change (proposed, it is small) or later with a race mode.
