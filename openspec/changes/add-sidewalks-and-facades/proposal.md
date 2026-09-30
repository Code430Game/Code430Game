# Change: Add sidewalks and building facades

**Status: APPROVED by the human on 2026-09-30** (asked for after the first downtown drive: "most of it is sidewalks", "buildings are quite stark").

## Why
Downtown blocks are grass up to the building walls, and every building is a flat-shaded box. Sidewalks are already in OpenStreetMap as footways, and a per-storey window shader fakes facades convincingly without any modelling. Both are cheap and change the look of the city more than anything else left on the list.

## What Changes
- **Sidewalks**: the import tool already exports pedestrian ways. The game builds ribbons for footways tagged as sidewalks (and other footways and paths), light concrete colour, with a small curb step above the road surface, chunked like roads and included in GLB export. Terrain is flattened under them at pack build like roads. Width from OSM `width` when present, else a per-class default.
- **Facades**: building walls get UVs in metres (u along the wall, v up the wall) and a facade shader that draws windows per storey using the importer's storey height. Four treatments selected by building type and height with a per-building seed: brick with punched windows, glass grid, stone with tall windows, plain panels. Roofs stay flat with a parapet darkening.
- **Not in this change:** curb cuts, crosswalks, street furniture, doors, actual textures or photo materials, roof shapes.

## Impact
- Affected specs: `street-dressing` (new).
- Affected code: `tools/osm_import` (pedestrian widths, terrain flatten under sidewalks), `game/world/roads/sidewalk_builder.gd` (new), `game/world/buildings/` (UVs, `facade.gdshader`, treatment rules), `map_pack.gd`, `glb_chunks.gd`.
- Performance: sidewalks add ribbon triangles on the order of the road count; the facade shader is a few texture-free math ops per pixel. Deck render time to be recorded.
