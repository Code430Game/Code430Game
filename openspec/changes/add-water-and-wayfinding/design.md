## Context
The road graph and terrain exist (`add-osm-road-import`). OSM water is polygonal: closed ways with `natural=water`, or multipolygon relations whose member ways must be stitched into rings. Large rivers are relations that extend far beyond the district, so rings must be assembled from full member geometry and then clipped to the bbox.

## Goals / Non-Goals
- Goals: recognizable rivers and canal; the player always knows the road they are on; a map they can open to orient themselves; all data-only in the pack.
- Non-Goals: animated water, reflections beyond the preset's SSR, boats, routing.

## Decisions
- **Fetch.** Overpass query for `natural=water` ways and relations plus `waterway=riverbank` in the bbox with `out geom` so member ways carry coordinates even outside the bbox. Cached like the highway query.
- **Assemble.** Standard multipolygon assembly: join member ways end to end into closed rings, classify by role (`outer`/`inner`) and containment. Unclosed rings after assembly are logged and dropped.
- **Clip and triangulate.** Rings become `shapely` polygons, intersected with the bbox rectangle, then triangulated with `mapbox_earcut` (handles holes). Output per polygon: name, OSM id, water type (`river`, `canal`, `lake`), triangles in local metres, and `surface_y`.
- **Surface height.** The median terrain height sampled inside the polygon, minus nothing; the DTM's water surface is already flat. Terrain cells inside the polygon are lowered by a small depth (config, ~1.5 m) at pack build so the shoreline has a visible bank, while roads on causeways stay flattened.
- **Rendering.** One `MeshInstance3D` per water polygon per chunk (split by the same 256 m grid), a `StandardMaterial3D` with a blue albedo, low roughness, and `deck` preset without SSR; `high` may enable SSR. Water has no collision in this change; driving into the river is a later concern (the auto-recovery puts the car back on a road).
- **Road name HUD.** Nearest edge via the graph's segment index every 0.25 s. Shows the edge name (or class when unnamed) and the name of the next cross street: the first junction ahead along the edge whose other incident edges have a different name.
- **Overview map.** A `SubViewport` renders the road graph lines (coloured by class, one-way arrows omitted) and water polygons once into a texture covering the pack bbox at a fixed metres-per-pixel. The map screen shows the texture in a `TextureRect`, centred on the player, rotated north-up, with a player marker and heading, zoomed by the triggers. Toggle on Back (View) alone; the debug combos stay on Back plus a face button.

## Alternatives considered
- Deriving water from the DEM (flat low areas): brittle, misses the canal, and gives no names. Rejected.
- Rendering the overview map from a live top-down camera: costs a full extra render every frame and shows unlit geometry. Rejected in favour of a cached graph texture.

## Risks / Trade-offs
- Ring assembly on real data is messy (gaps, shared ways, tagged both ways). Mitigation: drop and log; the report lists unassembled relations by id.
- Water polygons cut at the bbox edge look artificial. Mitigation: the world already ends there; a later boundary treatment applies to everything.

## Migration Plan
None; `water.v0.json` is optional and the loader treats its absence as "no water".

## Open Questions
- Should the overview map also mark the player's spawn and, later, mission points? (Recommended yes, as a generic marker list.)
- Map style: black-on-parchment or dark mode with class colours? (Recommended dark, matching the debug graph colours the human has already seen.)
