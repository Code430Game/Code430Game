# Design: parking

## The road-graph decision, revisited
The 2026-09-30 call dropped aisles and driveways because they add short, badly connected
edges that traffic wandered into and the validation report could not tell from real streets.
Both problems are addressed by class, not by dropping: `parking` edges are never chosen by
traffic (the `parking_only` lane flag, same mechanism as `bus_only`), and the report lists
them under their own class so dead-end and island counts for real streets are unchanged.
The win is that 595 driveways and 650 aisles reconnect the private-road islands and give the
player somewhere to pull off every street.

## Stalls from aisles
- `stall_dir` is the direction of the longest `parking_aisle` edge whose polyline lies inside
  the lot ring; without one, the longest ring edge. Stalls are laid along each aisle on both
  sides at `stall_width_m` (2.6) spacing, `stall_depth_m` (5.5), skipping any stall whose
  rectangle leaves the ring, overlaps a building footprint, a driveway, another stall, or
  comes within 1 m of the ring edge at an entrance.
- Lots with no aisle inside (small lots, 60 % of them) get one virtual aisle along the ring's
  longest axis through the centroid, so even a 10-car lot has stalls.
- `orientation=diagonal` tilts stalls 45 degrees along the aisle direction;
  `orientation=parallel` and all street-side bays use 6.5 m by 2.2 m stalls along the kerb.
- `capacity` where tagged caps the stall count; the report records how often the laid-out
  count disagrees with the tag by more than 30 %.

## Parked cars
- Deterministic: `rng.seed = hash(lot_id) ^ hour_bucket`, one hour bucket per 3 hours, so a
  lot fills and empties through the day without cars flickering between ticks.
- Occupancy table in `parking_config.json`: downtown (`fee=yes` or an operator) 0.8 by day
  and 0.3 at night, residential 0.4 by day and 0.75 at night, street bays 0.6 and 0.85.
- Rendering reuses the traffic MultiMesh per catalogue class and LOD, one set per chunk, so
  a parked car costs the same as a traffic car at rest. Colours from the catalogue palette.
- Bodies: the traffic body pool already assigns bodies to the nearest agents; parked cars
  register as zero-speed agents in a separate list that the pool considers after moving
  traffic, capped at `parked_bodies_max` (8 on deck, 16 on high). A parked car without a body
  is passable, exactly as a traffic car without a body is today; the pool radius covers every
  car the player can reach at speed, so the gap is never seen from the driver's seat.
- Taking: interact next to a parked car with a body works as taking a traffic car; the stall
  is marked taken for the session on the host and the car becomes a traffic-style agent the
  player drives.

## Map
Lots draw as a slightly lighter grey than buildings under the roads on the overview and the
minimap, from `parking.v0.json` rings. Street bays are not drawn on the map.

## Budget

| | deck | high |
|---|---|---|
| parked cars per chunk | 120 | 300 |
| LOD0 distance | 80 m | 150 m |
| bodies for parked cars | 8 | 16 |
| stall markings | marking quads, no cap (about 10 per car) | same |

## Decisions for the human
- Keeping aisles and driveways in the graph reverses the 2026-09-30 decision; confirm.
- Multi-storey garages: leave as plain buildings now (proposed) or hold this change until
  ramps and decks exist?
- Fee lots fuller by day than free residential lots is a guess at Ottawa; fine as a start?
