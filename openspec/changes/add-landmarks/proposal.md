# Change: Landmarks (Parliament first)

**Status: proposed 2026-10-09 (human: "for the Ottawa one, can we do a custom model of Parliament? Like the main building first — that way we can show some custom more realistic buildings where the auto-generated ones are not sufficient").**

## Why
Some buildings are what a city is recognised by, and generating them from OSM footprints fails
badly. On Parliament Hill today:
- **Centre Block** (`w68588665`, tagged `public`) comes out as a 3 m slab on the lawn;
- **the Library of Parliament** (`w128127770`, tagged `commercial`, 58 m) comes out as a round
  apartment tower with windows;
- **the Peace Tower** isn't there at all;
- the lawn in front is filled with scattered trees.

Packs need a way to replace generated buildings with a hand-made model where it matters, and
Parliament is the first one worth doing.

## What Changes
- **A landmark format.** A map pack may add `landmarks.v0.json`. Each landmark has:
  - the OSM building ids it replaces (they are not generated);
  - a position, heading and ground height;
  - a model, as either a **part list** (boxes, prisms, gables, pyramids and spires, cylinders,
    arched window rows, crenellations, each with a material from a small palette), built in
    code so models are diffable and an agent can author them, or a **glTF/GLB** file in the
    pack (allowed in data packs by `AGENTS.md`), for a human artist later;
  - a simplified collision shape;
  - LOD1 as the same parts without small detail;
  - optional tone variants (part overrides per content mode, e.g. dystopia banners on the
    tower);
  - areas to keep clear of scattered vegetation (the lawn).

  Schema, pack validator and a loader in the game (`LandmarkBuilder`), chunked and streamed
  like buildings.
- **Parliament, first pass** (in the Ottawa pack, as a part list):
  - **Centre Block:** a long Gothic Revival block in buff sandstone with green copper roofs,
    pointed-arch windows in rows, corner turrets and pavilions. Proportions are taken from
    reference measurements recorded in `design.md`, with sources.
  - **The Peace Tower** at its centre, 92.2 m, with a clock face on each side and a copper spire.
  - **The Library of Parliament** behind it: a sixteen-sided drum with flying buttresses and
    a copper lantern roof.
  - The front lawn kept clear, and the Centennial Flame as a small part.
  - East and West Blocks are follow-ups in the same format.
- **Not in this change:** interiors, other landmarks (the Château Laurier, the National Gallery
  and the Rideau Canal locks are natural next ones), and a model editor.

## Impact
- Affected specs: `map-buildings` (ADDED: Landmark Models Replace Generated Buildings).
- Affected code: `docs/pack-format/landmarks.schema.v0.json`, `tools/pack_tools` (validation),
  `game/world/buildings/landmark_builder.gd` (new), the building builder (skip replaced ids),
  vegetation (clear areas), the map pack loader and streamer; `packs/ottawa-centretown/landmarks.v0.json`;
  tests; screenshots of the Hill from Wellington Street and from the river.
- Performance: one landmark is a few thousand triangles at LOD0. Benchmark looking at the Hill
  on the Deck.
- See `design.md` for the format and the open questions.
