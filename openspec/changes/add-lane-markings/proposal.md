# Change: Add lane markings

**Status: APPROVED by the human on 2026-09-30** (ordered lane markings, then buildings, then the on-foot player).

## Why
Driving is the fun part right now, and a plain grey ribbon gives no sense of lanes, direction, or speed. The graph already knows lane counts and one-way direction, so markings are pure generation.

## What Changes
- Generated marking geometry per chunk from the road graph: yellow centre line on two-way roads (double solid on multi-lane, single dashed on two-lane residential), white dashed dividers between same-direction lanes, white solid edge lines. Canadian conventions.
- Markings follow the same trimmed polylines as the road ribbons, so they stop at junctions. Junctions get no markings in this change.
- One `markings_lod0` mesh per chunk, unlit-looking material, visible to 300 m, included in the GLB chunk export and import.
- Class-specific rules in a config table (dash length, gap, line width, which classes get a centre line): no magic numbers.
- **Not in this change:** stop lines, crosswalks, arrows, turn lanes, textures, junction markings.

## Impact
- Affected specs: `road-markings` (new).
- Affected code: `game/world/roads/marking_builder.gd` (new), `map_pack.gd`, `glb_chunks.gd`, `road_classes`-style config in `game/world/roads/marking_rules.json`.
- Performance: thin quads, roughly two to four times the road triangle count (about 60k triangles district-wide), negligible.
