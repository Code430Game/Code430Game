# Change: Character detail

**Status: proposed 2026-10-01 (human: "would love to see improved detail"; "the character detail sounds really awesome").**

## Why
The first creator shipped a box person. Rounder parts, a face, hair styles, beards, glasses
and jackets make a body worth customising, and a walk cycle makes it a person instead of a
sliding statue. Pedestrians wearing the same bodies make the streets match.

## What Changes
- **Body v2:** head, torso, limbs and hands from low-poly spheres, capsules and cylinders
  baked into one vertex-coloured surface; eyes, brows, nose, mouth; hair styles bald, short,
  long, bun, mohawk, ponytail; beard none, stubble, full; glasses; jacket with its own colour
  over the top. Still one draw call per body.
- **Rig and walk cycle:** eleven bones (hips, spine, head, arms in two parts, legs in two
  parts). `CharacterRig` poses them from a procedural walk cycle driven by distance moved,
  blending in with speed. Player, remote players and the creator preview use it.
- **Pedestrians:** eight pre-posed bodies from seeded random profiles, one MultiMesh each;
  agents are spread across them by colour. Replaces the tinted capsules.
- **Creator:** new rows for jacket, jacket colour, beard and glasses; the preview walks on
  the spot while turning.
- **Not in this change:** facial animation, clothing meshes beyond colour, LOD bodies.

## Impact
- Affected specs: `player-character` (modified requirement: Character Profile).
- Affected code: `character_mesh.gd` (rewritten), `character_rig.gd` (new),
  `character_profile.gd`, `player.gd/.tscn`, `remote_player.gd`, `character_creator`,
  `pedestrian_manager.gd`, tests.
- Performance: about 1,500 triangles per body; pedestrians eight draw calls instead of one.
  Deck measured.
