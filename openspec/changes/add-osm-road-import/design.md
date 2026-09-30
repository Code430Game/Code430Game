## Context
OSM describes roads as a navigation graph: ways (polylines) connected at shared nodes, with tags. It is excellent at topology and weak at exact geometry: intersections are single points, widths are often missing, there is no elevation, and interchanges are stacked only via `layer` tags. The pipeline must turn a topologically correct graph into believable, drivable 3D geometry without breaking that topology.

## Goals / Non-Goals
- Goals: correct connectivity, drivable geometry, believable junctions and interchanges, deterministic output, Deck-friendly meshes.
- Non-Goals (this change): buildings, traffic AI, pedestrians, lane markings beyond a basic center/edge line, runtime streaming (chunks are generated now; streaming comes later).

## Decisions

### Pipeline stages
1. **Fetch.** Overpass API for a bbox during development; option to read a Geofabrik Ontario `.osm.pbf` for reproducible builds. Cache under `tools/osm_import/.cache/` (gitignored). Record source and timestamp.
2. **Filter.** Keep `highway=*` drivable classes (motorway through residential/service, plus `*_link`), and footways/paths separately for later pedestrian use.
3. **Project.** EPSG:4326 → EPSG:32618 (UTM 18N), then offset to a local origin at the district center. Meters, Y-up.
4. **Build graph.** Nodes = OSM nodes that are junctions or way endpoints; edges = way segments between them with full polylines. Keep `osm_way_id`/`osm_node_id` for traceability.
5. **Fill defaults.** Missing `lanes`, `width`, `maxspeed` filled from a per-class defaults table in a config file (not hard-coded). Record which values were defaulted.
6. **Cluster junctions.** Merge junction nodes within a class-dependent radius (e.g., ~15 m for divided arterials) so dual-carriageway crossings become one junction. Never merge across different `layer` values.
7. **Elevation.** Sample a DEM (NRCan HRDEM/CDEM) for ground height. Bridges rise by `layer × clearance` (config, ~6 m) with smooth ramps that respect a maximum grade; tunnels descend likewise. Smooth road profiles to a maximum grade per class.
8. **Validate.** Write a report (JSON + human-readable Markdown) listing disconnected components, dead ends (classify likely-real ones such as `noexit=yes` or service roads vs. likely artifacts at the bbox edge), `*_link` ways that don't connect a motorway to another road, and strongly-connected-component analysis for one-way traps.
9. **Export.** `road_graph.v0.json` with a JSON Schema in `docs/pack-format/`.

### Road graph format v0 (summary)
- `meta`: schema version, origin (lat/lon + UTM), bbox, sources with timestamps, attribution strings.
- `nodes[]`: id, position [x,y,z], osm ids, junction type.
- `edges[]`: id, from, to, polyline [[x,y,z]…], class, lanes_forward, lanes_backward, oneway, speed_kph, width_m, layer, bridge, tunnel, name, osm_way_id, defaulted_fields[].

### Mesh generation (Godot)
- An editor tool script reads the graph and writes chunk data for the map pack. Because map packs are data-only (AGENTS.md), meshes are exported as **GLB per chunk**, not `.tscn`/`.res`.
- Roads: extrude cross-section along the polyline, width from lanes × lane width.
- Junctions: offset each incoming road's edges, intersect neighbors to find corner points, build a junction polygon, triangulate. Road ends are trimmed back to the junction boundary.
- Terrain: heightmap from DEM per chunk, flattened under road footprints with blended shoulders.
- LOD0/LOD1/LOD2 per chunk. Trimesh collision for road and terrain.

### Why Python for the pipeline
Mature geospatial libraries (osmium/pyosmium, shapely, pyproj, rasterio, networkx), strong AI familiarity, easy to test. Godot only consumes the output.

## Risks / Trade-offs
- **Interchanges are the hard case.** Stacked ramps, cloverleaf loops, and layer tags that don't match reality. Mitigation: dedicated fixture tests on the 417 interchange; per-edge manual override file in the map pack (`overrides.json`) for fixes that OSM data can't express.
- **Junction geometry artifacts** at sharp angles or many-way junctions. Mitigation: fallback to a simple convex hull polygon, flagged in the report.
- **OSM data quality varies.** The validation report surfaces problems rather than hiding them. Fixes that belong upstream should ideally be made in OSM itself.
- **Bbox edges create fake dead ends.** Classify edge-touching dead ends separately; later, map packs define a world boundary.

## Open Questions
- ~~Exact bbox for the starter district.~~ **Confirmed 2026-09-30:** Ottawa, Ontario, lat 45.405–45.435, lon −75.715 to −75.675. Covers Centretown, Parliament Hill, the ByWard Market / Lowertown, and the 417 including the Nicholas St interchange. The tool still takes the bbox as a parameter; this is the default in the starter pack config.
- DEM source and resolution: HRDEM where available, else CDEM. Confirm the license text for credits.
- Driving side and signage conventions are Canadian (right-hand traffic, km/h). Confirm no other assumptions are needed.
