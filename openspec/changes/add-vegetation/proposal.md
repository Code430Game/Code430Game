# Change: Trees and bushes

**Status: proposed 2026-10-02 (human: "we need to add trees and bushes").**

## Why
The district is roads, buildings and grass. Ottawa's downtown is full of street trees, the
canal banks and Major's Hill are wooded, and the parks are the gaps the city breathes
through; without them every block reads as a car park. OpenStreetMap already carries most of
it: individual `natural=tree` nodes along the streets, `natural=tree_row` ways, and park,
forest and grass polygons. The question the human asked is whether it fits the Deck budget:
it does if trees are instanced per chunk, carry LODs, and are capped per preset.

## What Changes
- **Importer.** A new stage `vegetation.py` with its own Overpass query (the water and
  buildings pattern): `natural=tree` nodes, `natural=tree_row` ways, and `natural=wood`,
  `natural=scrub`, `landuse=forest`, `landuse=grass`, `leisure=park`, `leisure=garden`
  polygons including multipolygon relations (`assemble_rings`). Export `vegetation.v0.json`:
  `trees` (x, z, y from the terrain, archetype, height, crown radius, seed, source `tagged`,
  `row` or `scatter`), `bushes` (same, smaller), and `areas` (park and grass polygons with
  triangles, for the map). Tagged trees keep their position, species or genus or `leaf_type`
  mapped to an archetype, `height` and `diameter_crown` when present. Rows are densified at a
  spacing. Polygons are filled with a Poisson-disc scatter seeded by the polygon's OSM id with
  a minimum spacing per land use. Bushes go along park edges and residential frontages where
  the gap between sidewalk and building face allows. Everything is kept off road footprints,
  sidewalks, building footprints, water and underpass trenches by a margin, using the
  distance-field helpers already in `pack.py`. Schema `vegetation.schema.v0.json`; the pack
  validator checks it; counts and skip reasons in the validation report. Deterministic:
  same input and seed, byte-identical output.
- **Game.** `VegetationBuilder` builds, per chunk, one MultiMesh per archetype and LOD from the
  JSON at chunk load (not baked into the GLB): LOD0 full low-poly mesh (trunk plus canopy, a
  tree under 150 triangles, a bush under 40), LOD1 a two-quad cross impostor with the
  archetype's silhouette and colour, nothing beyond. Three tree archetypes (broadleaf round,
  broadleaf columnar, conifer) and two bush archetypes, built from primitives in code; no
  textures, no billboards facing the camera. Per-instance colour varies by seed within a
  season palette (summer by default; the day-night `world-time` later picks autumn). LOD
  follows the streamer's chunk tier, not visibility ranges: NEAR chunks get LOD0 and LOD1 with
  a per-chunk distance split, MID chunks LOD1 only, FAR nothing, so no city-wide MultiMesh and
  no bounding-box-centre range bug. Collision: cylinder shapes for trunks within a margin of a
  road, NEAR tier only, added to the chunk's collision body through the existing shape queue.
  Wind sway: a vertex shader offset on canopies, on in `high`, off in `deck` (both presets
  declare it in `presets.json`).
- **Caps.** Per chunk per preset: `deck` 400 trees and 600 bushes, `high` 1200 trees and 2000
  bushes; the importer writes trees in priority order (tagged first, then rows, then scatter
  by seed) so a cap drops scatter first and keeps the real street trees. Draw calls stay at
  archetype times LOD per chunk (10 at most for a NEAR chunk).
- **Map.** The overview map and minimap fill park and grass areas green under the roads,
  above the building fill.
- **Not in this change:** grass blades or ground cover, hedges as walls, seasonal change with
  the clock, trees that break or fall when hit, flowerbeds, planters, street furniture.

## Co-op authority
Static world geometry built from pack data on every peer; nothing replicated.

## Tone
Not content; no descriptors, no variants.

## Impact
- Affected specs: `vegetation` (new), `wayfinding` (new requirement for the park fill).
- Affected code: `tools/osm_import/vegetation.py` (new), `__main__.py` (fetch and stage),
  `pack.py` (exclusion helpers reused), `validation.py` (report), `docs/pack-format/vegetation.schema.v0.json`,
  `tools/pack_tools/validate.py`, `tools/tests/test_osm_vegetation.py`, golden fixture;
  `game/world/dressing/vegetation_builder.gd` (new), `tree_meshes.gd` (new), `canopy.gdshader`
  (new), `game/world/packs/map_pack.gd` (load JSON, hand chunks to the builder),
  `game/core/streaming/chunk_streamer.gd` (tier-driven LOD swap, trunk shapes),
  `game/core/settings/presets.json` (sway, caps), `game/ui/map/map_renderer.gd` (areas),
  `game/tests/test_vegetation.gd`; Ottawa pack re-exported.
- Performance: worst case on `deck` is nine NEAR chunks at cap, 3,600 trees at LOD0 or LOD1
  and 5,400 bushes, under 600k triangles and under 90 draw calls; expected typical downtown
  chunks are far below cap. Measured on the Deck on the autodrive route and along the canal.
