# Design: features, LODs, vertex-animated crowds

## One profile, three meshes
- `CharacterMesh.build(profile, pose, skinned, lod)` keeps the LOD0 path and adds two reduced
  builders that use the same bone pivots so the walk shader and the skeleton pose all three.
  LOD1 drops eyes, brows, mouth, glasses frames and beard geometry (beard becomes a face tint),
  uses the lower-segment primitives, and merges hat and hair into one cap. LOD2 is eleven boxes.
- Triangle budgets are tests, not comments: LOD0 ≤ 1,700, LOD1 ≤ 500, LOD2 ≤ 100 for the
  heaviest profile (long hair, long coat, backpack, headphones).
- Visibility ranges follow `MapPack.LOD_FADE_M` fading: 0–60 m, 60–150 m, 150–350 m. Remote
  players and the player use the same ranges; the player's own body is always LOD0.

## Garments as geometry
- A garment is a set of primitives attached to the same bones as the body part it covers,
  slightly larger (coat skirts hang from `hips`, hood from `head`, backpack from `spine`).
  Patterns are vertex colours alternated per segment on the torso capsule, so no textures and
  still one surface per LOD.

## Vertex walk shader
- At build time each vertex gets its bone index in `CUSTOM0.r` and the bone's pivot (model
  space at scale 1) is known from `CharacterMesh.BONES`. The pool's height and build scale are
  shader uniforms (fixed per pool), the pivots a uniform array of eleven.
- `INSTANCE_CUSTOM` carries `phase` (0–1) and `amount` (0–1); the shader computes the eleven
  bone rotations from the same sinusoid table as `walk_pose` (ported, and a test compares one
  phase CPU vs shader by reading back a baked mesh), then applies parent-then-child rotation for
  the two-level limbs. Hips bob and spine twist come along.
- `PedestrianManager.step` already tracks speed per agent; it adds a stride phase per agent
  (`distance / STRIDE_M`) and writes phase and amount into the custom data when it writes the
  transform. Mirror mode on clients gets phase from the snapshot (one extra float per agent).
- `INSTANCE_COLOR` carries a skin tint and a top tint packed as two 8-bit hues; `CUSTOM0.g`
  marks which vertices take which tint (0 none, 1 skin, 2 top), multiplied in the fragment
  shader. Eight pools times the palettes give variety without more draw calls.

## Pools per LOD
- Each of the eight pools becomes three `MultiMeshInstance3D` (one per LOD) with the LOD's
  visibility range; an agent's instance lives in the pool matching its profile slot and is
  written into all three multimeshes with the same transform (hidden ranges cost nothing to
  draw). This avoids re-bucketing agents by distance every frame.

## Creator pages
- Five pages, switched with the shoulder buttons and shown as tabs; each page holds its rows,
  the preview stays. Randomise and presets remain on every page. `docs/controls.md` updated.

## Profile migration
- New fields have index 0 as "none" or the previous look, so `normalise` on an old dictionary
  reproduces the old body exactly. `CharacterStore` rewrites the file after a load that filled
  defaults.
