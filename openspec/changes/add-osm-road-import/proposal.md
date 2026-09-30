## Why
Hand-designed roads in open-world games are often incoherent: roads to nowhere, conflicting ramps, junctions that force U-turns. Real cities have already solved road layout. Importing OpenStreetMap road networks gives us correct topology (connections, one-ways, lanes, ramps, bridges) for free, and the same graph later drives AI traffic and GPS routing. This is the heart of Phase 1.

## What Changes
- New offline Python tool `tools/osm_import/` that takes a bounding box, downloads and caches OSM data and elevation data, and outputs a versioned road graph (`road_graph.v0.json`).
- Graph cleanup: merge dual-carriageway junction clusters, fill missing lanes/widths/speeds from road-class defaults, assign bridge/tunnel elevations from OSM `layer`, `bridge`, and `tunnel` tags.
- Graph validation report: disconnected components, suspicious dead ends, ramp connectivity, one-way traps (areas you can enter but not leave).
- Godot-side generator that builds road, intersection, and terrain meshes per 256 m chunk, with collision and LODs.
- A first map pack for the Ottawa starter district (Centretown, ByWard Market/Lowertown, a stretch of Highway 417 with at least one interchange).
- A drivable testbed: a placeholder car (Jolt `VehicleBody3D`) that can be driven on the generated roads.

## Impact
- Affected specs: `road-network` (new).
- Affected code: `tools/osm_import/`, `game/world/`, `packs/ottawa-centretown/`.
- Depends on: `bootstrap-godot-project`.
- Data licensing: map pack credits OSM (ODbL) and elevation source.
