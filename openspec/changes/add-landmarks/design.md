# Design: Landmarks

## Format: part lists first, glTF supported
- **Part lists** (JSON) are the default. Each part is a primitive with size, position, rotation
  and a material id: `box`, `prism` (extruded polygon), `gable` (a roof over a box), `hip`,
  `pyramid`, `spire`, `cylinder` (n sides), `window_row` (a row of arched or square openings
  cut as inset quads on a face), `crenellation`, `clock_face`. They are built in code into the
  same chunked meshes as other buildings. An agent can write and review them, they diff
  cleanly, and tone variants are part overrides.
- **glTF/GLB** is accepted for a landmark's model when a human artist makes one. Data packs may
  carry glTF (`AGENTS.md`), and Godot imports it at runtime without Godot resource formats. A
  glTF landmark still gives its collision as parts.

## Placement
A landmark is placed by local coordinates and heading, plus the ids of the generated buildings
it replaces. The building builder skips those ids, and the pack validator fails when a
replaced id doesn't exist (the OSM data moved).

## Materials
A small palette shared by every landmark: sandstone (buff), dark sandstone (trim), copper
(green patina), slate, glass, stone (grey), brick (red). The building shader takes them, so
night lighting and weather wetness work as on other buildings.

## Parliament references
Record each measurement with its source before modelling: the footprints from OSM (already in
the pack), the Peace Tower's height (92.2 m), the Centre Block's storeys and roof heights, and
the Library's drum diameter and height from public references. Where a number can't be
sourced, match the OSM footprint and photos, and say so here.

## Open questions
1. Should landmarks be allowed in story and character packs, or map packs only? (Proposed: map
   packs only.)
2. The Centre Block has been under renovation since 2019. Model it as it was before, or with
   scaffolding? (Proposed: as it was before; scaffolding could be a tone variant.)
