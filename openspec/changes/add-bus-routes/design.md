# Design: bus routes

## Routes from relations
OSM `route=bus` relations list ways and stop nodes in order, often in two relations per line
(one per direction) under a `route_master`. The importer keeps each direction as its own route,
maps each member way to the graph edges it became (an edge may come from a split way), closes
gaps between consecutive edges with a shortest path over bus-capable edges (bus-only, bus-lane,
and the `bus_classes` road classes) and records the number of closed gaps per route in the
validation report. Members outside the bounding box are dropped and the route is cut there,
which is what the district edge does to every road. Stops are relation stop members matched to
exported `bus_stops` by node id, else the nearest stop within 15 m of the route.

Synthetic routes: for every bus-only or bus-lane corridor not covered by a relation, walk the
corridor end to end, extend each end along the highest-class connected road until the district
edge or 1.5 km, and write a route with `synthetic: true`, `ref` from a running counter in the
900s and the corridor's street name. Deterministic from the graph, so golden tests hold.

## Placement by time
A route of length `L` with headway `h` and bus speed `v` has `n = ceil(L / (v h))` buses. At host
time `t`, bus `k` sits at distance `((t + k h) mod (L / v)) * v` along the route, smoothed by the
agent once it exists. The manager spawns route buses when a player's spawn radius covers the
position the formula gives and lets the agent drive from there; a bus that drifts (dwell,
traffic) is not snapped back, it is just late. Despawn as usual beyond the radius. This replaces
random bus spawning on route-covered lanes; `bus_share` still applies elsewhere.

## Lane choice
`TrafficAgent` gains `route_id`, `route_edge_index`, `stop_index`. The route-following filter
accepts the lane path on the route's next edge; when no lane path matches (off-route), the
filter accepts any bus-capable path and the agent searches ahead `rejoin_reach_m` for a route
edge, else clears `route_id` and roams as today.

## Signs and placards
Three digits per bus packed into one custom-data float (hundreds, tens, units in 0..9 each as a
10-based number), decoded in the body shader for the sign surface, which samples a 10-glyph
emissive atlas generated at startup in code (no textures in the repo). Placards use the same
atlas on a quad mesh per shelter or flag.

## Shelters
`BusStopBuilder` runs at chunk build next to the sidewalk builder: for a stop, find the sidewalk
ribbon on the stop's side within 6 m, place a 3.5 m by 1.5 m shelter (roof slab, three glass
panels, bench) or a 2.5 m pole with a flag, aligned to the ribbon, with a box collision shape.
LOD1 is the roof and posts only. Stops with no sidewalk nearby get a pole on the verge.
