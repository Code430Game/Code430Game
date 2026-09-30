# osm_import

Turns an OpenStreetMap extract into `road_graph.v0.json` plus a validation report. Schema: `docs/pack-format/road_graph.schema.v0.json`.

```
cd tools
uv run python -m osm_import --bbox 45.405,-75.715,45.435,-75.675 --out ../packs/ottawa-centretown/import --title "Ottawa Centretown"
```

Options: `--osm-json FILE` reads a saved Overpass JSON file instead of fetching (used by tests), `--config FILE` swaps the defaults table, `--cache-dir DIR` moves the download cache (default `osm_import/.cache/`, gitignored).

Fixtures: `python -m osm_import crop --osm-json CACHED.json --bbox S,W,N,E --out tests/fixtures/NAME.osm.json` cuts a committed test extract out of a cached download and records where it came from.

## Stages
1. **Fetch** Overpass `way["highway"]` for the bbox, cached by query hash with a sidecar recording endpoint, query, fetch time, and OSM base timestamp.
2. **Filter** (`filter.py`) drivable classes vs pedestrian classes. Drops construction/proposed, `area=yes`, parking aisles, driveways, and `access=no|private` unless `motor_vehicle` allows it. Dropped ways are remembered so the report can explain islands.
3. **Project** (`projection.py`) WGS84 to UTM 18N, then local metres with the origin at the projected bbox centre. x east, y up, z south.
4. **Build** (`graph.py`) nodes at junctions and way ends, edges with full polylines. Tags parsed leniently; missing lanes, width, speed filled from `road_classes.json` and listed in `defaulted_fields`. `oneway=-1` reverses the polyline; motorways and roundabouts imply one-way.
5. **Cluster** (`cluster.py`) contracts short edges between junctions so a divided road's two crossing points become one junction. Radius is the largest class radius at the junction. Never across layers, never a bridge or tunnel edge.
6. **Validate** (`validation.py`) connected components with a likely cause, dead ends in four categories, `*_link` chains that do not connect a major road at two points, and one-way traps via strongly connected components. Nodes within `bbox_edge_margin_m` of the bbox are reported as cut edges rather than problems.
7. **Export** (`export.py`) sorted keys, 3-decimal coordinates, no wall-clock timestamps in the output, so two runs on the same cache are byte-identical.

Elevation is not applied yet: every `y` is `0.0` and `meta.elevation` is `null`. That is stage 4 of the change.

## Tunables
All in `road_classes.json`: lane width, bbox edge margin, bridge clearance, per-class lanes, one-way lanes, speed, cluster radius, and max grade.

## Known trade-offs
- A driveway or service junction within the cluster radius of a big intersection gets pulled into it. Acceptable for v0; `overrides.json` in the map pack is the escape hatch later.
- Parking aisles and driveways are dropped, so some private roads become islands. The report names the filtered connector for each.
