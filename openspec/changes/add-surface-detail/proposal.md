# Change: Surface detail, sidewalk joints and zebra crossings

**Status: proposed 2026-10-02 (human, after a Deck drive: "we should add textures and sidewalk line breaks; the cross walks should be striped like Abbey Road"); approved 2026-10-04 (human: "i want to add textures to the surfaces too"), with the backlog's grass-through-roads fix folded in. The design's open decisions were taken from the human's request: zebra stripes on every crossing ("like Abbey Road"), and slab lengths of 1.5 m downtown and 2 m on paths.**

## Why
Roads, sidewalks and crossings are flat vertex colours: a sidewalk is one grey ribbon with no
slab joints, a crossing is a lighter strip flush with the road (`sidewalk_builder.gd`), and
asphalt has no grain. At Deck resolution the city reads as a diagram. Cheap world-space
detail fixes that without any per-chunk data: a generated detail texture set, expansion
joints on sidewalks, and zebra stripes on crossings.

## What Changes
- **Detail textures.** A small set generated in code at boot, deterministic, no assets: asphalt
  grain with faint tyre polish, concrete with aggregate speckle, a slab-joint line, paint
  with wear. Applied through world-space planar UVs in the shared road, sidewalk, marking and
  junction materials so chunks need no UV data. `deck` samples one 512 px set with no normal
  map; `high` samples 1024 px with a normal map and a roughness variation. Declared in
  `presets.json`.
- **Sidewalk joints.** Sidewalk ribbons get transverse joint lines every slab length
  (`slab_m`, default 1.5 m on downtown sidewalks, 2 m on paths) and a longitudinal joint on
  ribbons wider than 3 m, drawn as a dark line in the detail texture by distance along the
  ribbon, so wide and curved sidewalks still look poured in slabs. Curb face keeps its own
  tone. Driveway cuts and corner ramps come later.
- **Zebra crossings.** Crossings become white stripes across the road, 0.5 m wide at 0.5 m
  gaps, aligned with the crossing's direction and stopping at the curb, with a stop line on
  the approach where the crossing is signalised (`crossing=traffic_signals` or a junction
  with signals); unsignalised crossings get the same stripes, which is the human's preference
  over Ottawa's two-line markings. Stripes are marking quads in the marking chunks, using the
  paint detail so they wear like the lane lines.
- **Grass through roads (folded in from the backlog, 2026-10-03).** Terrain still shows through
  some junction surfaces, mostly in the corners between arms, because the importer flattens the
  terrain only under edge ribbons. It now also flattens a disc under every junction node at the
  node's height, sized from the widest arm, and a test on the Ottawa pack counts junction
  surfaces with terrain poking through, before and after.
- **Not in this change:** road patches and potholes, manhole covers and drains (vegetation and
  underpass rounds own grates), textured building facades, decals from combat.

## Co-op authority
Static geometry; nothing replicated.

## Tone
Not content. Wear and dirt levels may later read the mode's variant key; not now.

## Impact
- Affected specs: `street-dressing` (Sidewalks From Footways modified, Zebra Crossings added),
  `road-markings` (no requirement change: the crossing stripes use the marking chunks and the
  existing rules file).
- Affected code: `game/world/build/` (detail texture generator, new), `game/world/roads/road_mesh_builder.gd`,
  `junction_builder.gd`, `marking_builder.gd`, `sidewalk_builder.gd`, their materials and
  shaders, `game/core/settings/presets.json`, `docs/graphics-presets.md`, tests on the stripe
  count and joint spacing; Ottawa pack re-exported only if the sidewalk GLB role needs the
  distance attribute (design decides).
- Performance: texture samples per pixel go up by one on `deck` and three on `high`; no new
  draw calls on `deck`. Deck measured on Bank Street and the Market.
