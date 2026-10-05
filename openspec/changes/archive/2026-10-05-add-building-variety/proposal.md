# Change: Building variety from data

**Status: proposed 2026-10-01 (queue item: building variety; approved in conversation "That sounds really good for buildings").**

## Why
Every building is a flat-roofed extrusion with one of three facades chosen by kind and height,
so blocks of similar buildings read as one grey mass. OpenStreetMap carries more than the game
uses: colour, material, roof shape, shop and amenity, and the footprint's own proportions. Using
that first, and a per-building seed only for the gaps, keeps the city recognisable and
deterministic while making streets look like streets.

## What Changes
- **Importer:** buildings carry `material`, `colour`, `roof_shape`, `roof_levels`, `levels`,
  `shopfront` (shop, amenity or retail kind) from OSM tags; schema bumped.
- **Facades:** six treatments instead of three: plain, punched brick, stucco (small windows,
  warm), precast (wide bands), glass grid, curtain wall (all glass, mullions), and stone tall.
  Treatment picks from material first, then kind and height; `building:colour` overrides the
  kind colour; seed picks within a treatment's palette.
- **Roofs:** gabled and hipped roofs for houses and small buildings tagged or inferred
  (`roof:shape`, else houses under 12 m get a gable along the long axis); a parapet lip on flat
  roofs over 8 m; mechanical boxes on roofs over 30 m. Pitched roofs are built from the footprint's
  oriented bounding box so odd footprints still get a sane roof.
- **Ground floors:** shopfronts on buildings with a shop or amenity tag or retail kind: a taller
  glass ground storey with an awning band in a seeded colour on every wall longer than 6 m.
- **Balconies:** apartment blocks over 12 m get balcony slabs on the long sides every storey.
- **Not in this change:** `building:part` massing for landmarks, interiors, signs, textures.

## Impact
- Affected specs: `map-buildings` (modified).
- Affected code: `tools/osm_import/buildings.py`, schema; `game/world/buildings/building_builder.gd`,
  `facade.gdshader`; GLB generator version; tests on both sides.
- Performance: more triangles per building (roofs, balconies); Deck measured downtown before and after.
