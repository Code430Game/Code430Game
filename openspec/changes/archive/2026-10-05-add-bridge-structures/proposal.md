# Change: Bridge structures

**Status: proposed 2026-10-05 (human, after the first Deck round of the day: "I wonder if there are other things that would be benefitted by a more concrete bridge implementation. We are missing the walkways and concrete when we look up too. I wonder if better bridge detection might help for these? The bridges over the water are probably good examples to look at too.")**

## Why
Bridges are drawn as ordinary road ribbons lifted to their layer's height. A ribbon has one
face, pointing up, so from below a bridge is see-through. Only the parapets and kerbs are
boxes, which is why the 417 over Metcalfe reads as white planks floating in the sky
(report #27). Nothing holds a deck up, the ground around an abutment is wherever the terrain
happens to be, and the walkways that ride along a deck are drawn wherever their own data puts
them. A survey of the Ottawa pack (2026-10-05) found:
- 62 bridge edges, about 4 km in all (17 motorway, 38 primary or secondary). The longest is
  400 m, the median 27 m. The canal and river crossings are among them.
- 76 bridge footways and cycleways, all in the pack. 41 run beside a deck at deck height, and
  5 run beside a deck 2 to 12 m below it, on the ground. That fits the human's report that the
  lower road's sidewalks sometimes look attached to the upper road.
- 42 bridge roads carry sidewalk tags (`both`, `right`, `separate`), which the sidewalk
  builder does not read for decks.
- The importer does not fetch `man_made=bridge` outlines, the bridge footprints that mappers
  draw, so "where is the bridge" is known only from `bridge=*` on each way, segment by segment.

## What Changes
- **Detection (importer).**
  - Group consecutive `bridge=*` edges, and parallel carriageways within a gap, into one
    bridge with an id, span, deck level, kind (road over road, over water, over rail,
    footbridge) and abutment ends.
  - Fetch `man_made=bridge` outlines where they exist. They take precedence for the deck's
    footprint (shared decks, the walkway width).
  - Export `bridges.v0.json` with a schema, validated by `pack_tools`.
- **Deck (game).** Each bridge gets a solid deck instead of a lone ribbon:
  - an underside (soffit) at the deck's depth (span-based, 0.8 to 1.8 m)
  - fascia faces along both edges
  - the walkway widths included when walkways ride along it
  - drawn with the concrete detail material from `add-surface-detail`, and part of collision
- **Supports.**
  - Piers under spans longer than `pier_spacing_m`: wall piers over roads, round columns over
    water, sitting on the terrain or the water floor and placed clear of the roads underneath
    (no pier in a lane).
  - Abutments at both ends: a sloped concrete face where the deck meets the embankment, so
    the terrain no longer shows a gap or pokes through.
- **Walkways.**
  - Bridge footways and the sidewalk tags of bridge roads are drawn on the deck, at deck
    height, with the parapet outside them.
  - Walkways that the data puts on the ground beside a deck are lifted onto it when they
    belong to that bridge (same OSM bridge, or inside its outline).
  - Ground sidewalks of the road underneath stay on the ground: no sidewalk is joined to a
    road on another layer.
- **Look-up check.** A screenshot test from under each kind of bridge (the 417 over Metcalfe,
  a canal crossing, a footbridge) shows the soffit, not the sky.
- **Not in this change:** moving or opening bridges, cable-stayed or truss superstructures
  (decks get a plain concrete girder look; a later change can style named bridges), lighting
  under bridges, and rail bridges (`add-rail`).

## Co-op authority
Static world geometry from the pack. Nothing is replicated.

## Impact
- Affected specs: `road-network` (ADDED: Bridge Structures).
- Affected code: `tools/osm_import/` (new `bridges.py`, query and export; walkway lift),
  `tools/pack_tools` (schema), `game/world/roads/` (new `bridge_builder.gd`; road mesh skips
  the ribbon under a deck), `game/world/roads/sidewalk_builder.gd` (deck walkways, layer
  check), `game/world/packs/map_pack.gd` (NEAR role `bridges_lod0`, collision), terrain holes
  or clamps at abutments, and the Ottawa pack (re-exported).
- Performance: a few hundred extra triangles per bridge; 62 bridges. Deck benchmark against
  main.
