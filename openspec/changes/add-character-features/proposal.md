# Change: Character features, body types, children in clean mode, prints on clothes

**Status: proposed 2026-10-02, rewritten 2026-10-08 after the human's brief: body types (body A / body B in clean), children in clean mode only, prints on tees and items with per-mode variants (emoji in clean, invented brands in gritty, aggressive marks in dystopia).**

## Why
`add-character-detail` gave the body rounded parts, a face, hair, beards, glasses, a jacket and
a walk cycle; the pedestrian round (2026-10-04) then made the crowd walk with it, one draw call
per body pool, and fall as ragdolls. Since then officers (`add-police`) and gang members
(`add-hostile-gang`) wear the same body as rigged actors. What is left is what you notice at a
glance and what the human asked for: everyone is the same shape, clothes are flat colours with
nothing printed on them, hats and hair run out after a few picks, a pedestrian two blocks away
costs as much as one beside you, and the clean mode's city has no children in it while the
other modes rightly must not.

## What Changes
- **Two body types** (human: "get a male female; on the PG mode maybe call it body A body
  B"). A profile field `body` with values `a` and `b`, each a base set of proportions
  (shoulders, hips, chest, neck, height and build defaults) that the existing sliders then
  adjust. The creator's row label and value names come from a strings table with per-mode
  variants: "Body: A / B" in `clean`, "Body: man / woman" in `gritty` and `dystopia`; nothing
  in code names a sex. Both bodies are worn by the player, remote players, pedestrians,
  officers and gang members; the population split per body is pack data with a base default.
- **Children, in clean mode only** (human: "the PG version could have kids but otherwise no
  since we don't want to kill kids"). A `child` body (shorter proportions, its own clothes
  set and hair picks) is content carrying a new `minors` descriptor. The descriptor's maximum
  is `none` in `gritty` and `dystopia` and `present` in `clean`, and the manager spawns
  children only where the mode's `violence` flag is false. Children are never a player body
  and never a target: weapons, paint, cars, officers and the gang pass them by in every mode
  (a car brakes for them as it does for an obstacle; no knock-down, no tag-out, no ragdoll).
  The mix of adults and children per mode is pack data. This narrows what a mode allows; it
  never widens it.
- **Prints on clothes and items** (human: "graphics on the T's / items; maybe grab some
  graphic library or knock off some brands and logos; PG could be emojis and light things,
  dystopia more aggressive"). A `prints.v0.json` content type: each print has descriptors and
  per-mode variants naming a cell in a print atlas PNG. Tops, hoodies, caps, bags and the
  gang's colours carry a print region sampled from the atlas by a per-instance print index,
  so the crowd stays one draw call per pool. The base set ships three sheets built by a script
  at build time, no hand-drawn art: `clean` renders emoji-style glyphs from an open emoji font
  (proposed Noto Emoji, OFL, see Decisions), `gritty` invents satirical brands and logos as
  simple vector marks the way the billboard ads invent theirs, `dystopia` draws aggressive
  marks (skulls, glitch, corp seals) from the same generator with its own palette. Packs ship
  their own atlas and prints file; the validator checks descriptors and that every variant's
  cell exists.
- **Garments and parts** (kept from the first draft): hoodie with hood up or down, long coat,
  shorts, skirt, boots, high-tops; striped and plaid tops; four more hair styles (buzz, curly,
  afro, braids); hats gain hood, wide brim and hard hat; eyewear gains sunglasses; accessories
  backpack, shoulder bag, headphones, face mask. New profile fields take defaults in
  `CharacterProfile.normalise`, so every saved character and preset still loads.
- **Face and build** (kept): eye colour, brow and mouth shapes, `belly` and `shoulders`
  sliders beside height and build.
- **LODs** (kept, still open): three meshes from one profile, LOD0 as today (about 1,500
  triangles), LOD1 without face parts and with simple hair and hats (about 450), LOD2 a
  jointed box figure (about 80); switched at 60 m and 150 m for the player's replica,
  pedestrians, officers and gang members alike. Pedestrian pools become three MultiMeshes
  each, one per LOD.
- **Per-instance tints** (kept, still open): skin, top and bottom hues per instance through
  the instance colour, so eight pools look like hundreds of people.
- **Creator pages** (kept): Body, Face, Hair, Clothes, Extras on the shoulder buttons so the
  row list fits the Deck's screen, with a print picker on the Clothes page.
- **Already done by the pedestrian round, dropped from this change:** the vertex walk shader,
  the walk phase and amount in the instance custom data, walking that blends to standing,
  and ragdoll falls. This change extends that shader (print cell, tints, LOD meshes) rather
  than replacing it.
- **Not in this change:** facial animation, cloth simulation, sheltering outfits and routines
  (`add-underpass-interiors`), archetype-driven outfits from a character pack (the fields and
  the print type exist; weighting them is pack content, see `add-pack-loader`), glTF body
  imports, child-specific behaviour beyond walking (no school runs, no dialogue).

## Co-op authority
Unchanged: each peer owns its profile and sends it on change; the profile dictionary grows
and older peers' missing fields take defaults. Pedestrian snapshots gain nothing new for
bodies and prints (both are derived from the agent seed on every peer); the mode is already
the host's for the session, so the child mix follows it everywhere.

## Tone
The body types carry no descriptors. The child body carries `minors` and is gated by the
mode's `violence` flag as well, belt and braces. Prints are content: `ContentMode.pick_variant`
chooses the cell per mode, and a print with nothing allowed in the mode draws plain cloth.
The creator's body labels are a strings variant. No mode id appears in gameplay code.

## Impact
- Affected specs: `player-character` (Character Profile and Character Creator modified),
  `pedestrians` (Walking Animation modified; Body Levels Of Detail and Children In Clean Mode
  added), `content-modes` (Content Descriptors modified: the `minors` descriptor with a
  migration note).
- Affected code: `game/actors/character/character_profile.gd` (body, child, prints, new
  fields, strings), `character_mesh.gd` (proportions per body, garments, parts, print UVs,
  `build(profile, pose, skinned, lod)`), `character_rig.gd` (three LOD instances), the walk
  shader `game/world/pedestrians/pedestrian_walk.gdshader` (atlas sample, tints, LOD meshes),
  `pedestrian_manager.gd` (pools per LOD, body and child mix, print index and tints in the
  instance colour), `game/actors/police/police_manager.gd` and
  `game/actors/factions/faction_manager.gd` (both bodies, the gang's print), the creator
  `game/ui/character/` (pages, print picker, strings), `game/core/content/strings.v0.json`
  and `prints.v0.json` (new), `content-descriptors.v0.json` and the three mode files
  (`minors`), `docs/pack-format/prints.schema.v0.json` and README, `tools/pack_tools`
  (prints and strings validation), `tools/prints/` (the atlas generator, new, run in CI
  with a committed output and a diff check), `LICENSE-ASSETS` and the base pack manifest
  (font attribution), tests throughout, `docs/controls.md`.
- Performance: pedestrians go from eight draw calls to 24 (eight pools by three LODs) with
  most instances at LOD1 or LOD2; one 1024 px atlas sample per fragment on clothed parts; the
  child body adds nothing beyond its share of the cap. Triangle counts per LOD are asserted
  in tests and the Deck is measured with `--peds` at the cap in every mode, before and after.
- Content policy: children appear only where violence is off and can never be targeted;
  no real brands, people or studio parodies in any print; the emoji font is the only
  third-party asset and needs the human's licence decision.
