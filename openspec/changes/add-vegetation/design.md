# Design: vegetation

## Sources and archetypes
| OSM | export | archetype |
|---|---|---|
| `natural=tree` node | one tree, `source: tagged` | from `leaf_type` (needleleaved → conifer), `genus`/`species` lookup table (Acer, Quercus, Tilia, Ulmus → broadleaf round; Populus, Fraxinus → columnar; Picea, Pinus, Thuja → conifer), else broadleaf round |
| `natural=tree_row` way | trees every `row_spacing_m` (8) along the way, `source: row` | as tagged, else broadleaf round |
| `natural=wood`, `landuse=forest` | scatter, spacing 6 m, mix 70 % broadleaf 30 % conifer | by seed |
| `leisure=park`, `leisure=garden` | scatter, spacing 14 m, bushes on the edge every 8 m inset 2 m | broadleaf |
| `landuse=grass` | scatter, spacing 25 m | broadleaf |
| `natural=scrub` | bushes, spacing 4 m | bush |
| residential frontage | a bush every 6 m where the strip between sidewalk edge and building face is at least 2.5 m wide, inset 1 m from the sidewalk | bush |

Heights: tagged `height` wins, else per archetype from a seeded range (broadleaf 7 to 14 m,
columnar 10 to 18 m, conifer 8 to 16 m, bush 0.8 to 1.6 m). Crown radius from
`diameter_crown` else 0.35 of height for broadleaf, 0.2 for columnar and conifer.

## Scatter
Bridson Poisson-disc sampling inside the polygon with the spacing above, seeded with the
polygon's OSM id so the result is stable across runs and independent of other polygons.
Candidates are rejected within the exclusion margin: road half width plus 2 m, sidewalk ribbon
plus 1 m, building footprint plus 1 m, water, underpass trenches. The distance field from
`pack.py` (`_distance_field`, `_segments_near`) is reused with the pedestrian ways included.
Each tree gets `y` from the final terrain sampler after flattening, so trunks sit on the ground
the player sees.

## Priority and caps
The importer writes each chunk's list in priority order: tagged trees, then rows, then
scatter sorted by seed. The game reads the first N per the active preset's cap and drops the
rest, so lowering a cap never removes a real street tree before a scattered one. The
validation report lists per-chunk counts and the number over cap at each preset.

## Meshes and LODs
Archetype meshes are generated in code once (`tree_meshes.gd`): an 8-sided trunk and a
canopy of two or three stacked low-poly ellipsoids (broadleaf), a tall ellipsoid (columnar),
or three stacked cones (conifer); bushes are a single flattened ellipsoid. Vertex colours
only; the canopy shader reads the instance colour and, in `high`, offsets vertices by a
seed-phased sine for sway. LOD1 is two crossed quads with the archetype silhouette as
vertex-coloured geometry (no texture), 4 triangles.

LOD selection is by chunk tier from the streamer, never by `visibility_range_*`, because a
MultiMesh's range is measured to its AABB centre. A NEAR chunk carries both LOD MultiMeshes
and the builder assigns each instance to LOD0 when it is within `lod0_m` (120) of the
nearest anchor at build time, refreshed when the chunk's tier is re-evaluated; a MID chunk
carries LOD1 only; FAR none. Instances past a chunk's cap are dropped at build.

## Collision
Trunk cylinders (radius 0.25 m, height 3 m) only for trees within 6 m of a road edge, NEAR
tier, queued through the streamer's shape queue like other chunk shapes. Bushes and park
interiors have no collision; the player walks through foliage.

## Presets
| feature | deck | high |
|---|---|---|
| trees per chunk | 400 | 1200 |
| bushes per chunk | 600 | 2000 |
| LOD0 distance | 120 m | 200 m |
| sway | off | on |
| trunk collision | near roads only | near roads only |

## Decisions for the human
- Collision on every trunk (a tree stops a car in every GTA) costs about one shape per tree
  in NEAR chunks; this pass keeps it to trunks near roads. Say if every tree should be solid.
- Season: summer palette only. Autumn with the clock is a follow-up.
