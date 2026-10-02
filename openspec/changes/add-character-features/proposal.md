# Change: Character features, LODs and animated pedestrians

**Status: proposed 2026-10-02 (human asked for a slate of proposals that other agents can pick up in fresh contexts; follows `add-character-detail`, which is awaiting its Deck gate; human: "would love to see improved detail").**

## Why
`add-character-detail` gave the body rounded parts, a face, six hair styles, beards, glasses, a
jacket and a walk cycle, and put pre-posed copies of it on the sidewalks. What is left is what
you notice at a glance: every pedestrian is one of eight frozen statues sliding along, clothes
are colours rather than garments, hats and hair run out after a few picks, and there is no LOD,
so 120 bodies at 1,500 triangles each are drawn in full from a block away. This change makes the
population move, look varied, and cost less.

## What Changes
- **Garments and parts:** hoodie (hood up or down), long coat, shorts, skirt, boots, high-tops;
  tops with a stripe or plaid pattern; four more hair styles (buzz, curly, afro, braids); hats
  gain hood, wide brim and hard hat; eyewear gains sunglasses; accessories backpack, shoulder bag,
  headphones, face mask. New profile fields with `CharacterProfile.normalise` filling defaults so
  every saved character and preset still loads.
- **Face and build:** eye colour, brow and mouth shapes, a `belly` slider and a `shoulders`
  slider next to height and build.
- **LODs:** every body builds three meshes from one profile: LOD0 as today (about 1,500
  triangles), LOD1 with hair, hat and accessories as simple shapes and no face parts (about 450),
  LOD2 as a jointed box figure (about 80). Player, remote players and pedestrians switch at the
  same distances (60 m, 150 m), pedestrians disappear at 350 m as now.
- **Animated pedestrians:** the eight pre-posed pools become eight *vertex-animated* pools: each
  vertex carries its bone index and the MultiMesh custom data carries the agent's stride phase and
  walk amount, and a vertex shader applies the same walk cycle as `CharacterMesh.walk_pose`. One
  draw call per pool per LOD, every pedestrian walking in step with its own speed. Per-instance
  tint (skin and top) through the instance colour widens eight bodies into hundreds of looks.
- **Creator:** rows grouped into pages (Body, Face, Hair, Clothes, Extras) selected with the
  shoulder buttons so the list stays short on the Deck's screen; the preview shows the LOD in
  use when zoomed out, for authors.
- **Not in this change:** facial animation, cloth simulation, sheltering outfits and routines
  (`add-underpass-interiors`), archetype-driven outfits from a character pack (the fields exist;
  weighting them is pack content for later), glTF body imports.

## Impact
- Affected specs: `player-character` (modified requirement: Character Profile), `pedestrians`
  (new requirement: Animated Pedestrian Bodies; the capability is pending in `add-pedestrians`).
- Affected code: `game/actors/character/character_profile.gd` (fields, defaults, names),
  `character_mesh.gd` (garments, parts, patterns, `build(profile, pose, skinned, lod)`),
  `character_rig.gd` (three LOD mesh instances with visibility ranges), `character_walk.gdshader`
  (new, the vertex walk), `game/world/pedestrians/pedestrian_manager.gd` (pools per LOD, custom
  data per instance, tints), `pedestrian_body.gd`, `game/ui/character/character_creator.gd/.tscn`
  (pages), `game/actors/player/player.tscn`, `remote_player.gd`, `docs/controls.md`, tests
  (`test_character.gd` triangle budgets per LOD, pool and shader phase tests, profile migration).
- Performance: today pedestrians cost eight draw calls at full detail; after, 24 draw calls (8
  pools by 3 LODs) with most instances at LOD1 or LOD2, and the walk moves to the GPU. The
  shader adds a few matrix operations per vertex. Triangle counts per LOD are asserted in tests
  and the Deck is measured with `--peds` at the 120 cap, before and after.
- Authority: unchanged, each peer owns its profile and sends it on change; the profile dictionary
  grows and older peers' missing fields take defaults. Tone: the body carries no descriptors;
  nothing here reads the mode.
