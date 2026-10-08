# Design: bodies, children, prints, LODs

## What the pedestrian round already did
`pedestrian_walk.gdshader` carries each vertex up its bone chain from `CUSTOM0.r` with the
walk pose from `INSTANCE_CUSTOM.x` (phase) and `.y` (amount); `.zw` hold paint marks from
`add-weapons-and-combat`. Eight pools each draw one MultiMesh; `PedestrianManager` writes
phase and amount beside the transform; `CharacterRagdoll` takes over on a hit. All of that
stays. The instance colour (`COLOR`, multiplied into the vertex colour when `use_colors` is
on) is unused today and is where this change puts tints and the print index.

## Two bodies, one builder
- `CharacterMesh` gets a proportions table per body: shoulder width, hip width, chest depth,
  neck length, default height and build, limb radii. `build(profile, …)` looks the table up by
  `profile.body` and the sliders scale from there, so every primitive placement reads from the
  table instead of a literal. `a` keeps today's numbers exactly, so old profiles and the eight
  committed pool looks do not change; `b` is narrower at the shoulder, wider at the hip,
  shorter by default.
- `child` is a third row in the same table (0.72 of the adult height, shorter limbs, a larger
  head ratio) with its own clothes and hair pick lists; `CharacterProfile.random` never
  produces it, `PedestrianManager` asks `CharacterProfile.child(rng)` for it explicitly.
- Strings: `game/core/content/strings.v0.json` holds UI strings that differ by mode as
  variants (`body.label`, `body.a`, `body.b` first; room for more). `ContentMode.text(key)`
  picks the variant. The creator reads labels through it; tests assert "A"/"B" in clean and
  "man"/"woman" otherwise.

## Children only where violence is off
- `minors` joins the closed descriptor list with levels `none` and `present` (a two-level
  descriptor; the schema already allows a per-descriptor level list via aliases, and the
  migration note says existing content without the key reads as `none`). `clean.json` sets
  `max.minors: present`; `gritty.json` and `dystopia.json` set `none`.
- `PedestrianManager` spawns a child only when `ContentMode.allows("minors")` and
  `not ContentMode.flag("violence")`, at the pack's `population.child_share` (base 0.12 in
  clean). Children walk with an adult when spawned in a pair (same seed, offset 1.2 m) so a
  child alone is rare.
- Untargetable: a `child` flag on the agent and on `PedestrianBody` (physics layer bit
  `CHILD`), checked in `Shooter._hit_pedestrian`, `PedestrianManager.hit_by_car` (the car gets
  the obstacle stop, the child steps aside, no knock-down and no ragdoll), the officer and
  gang target pickers, and the paint path (no tag-out either). Tests cover every one of those
  paths in clean, and that no child exists in gritty or dystopia regardless of pack data.
- Policy reasoning: the content policy forbids sexual content involving minors and the game is
  built so violence against anyone is a mode flag; children exist only in the mode whose flag
  is off and are excluded from every interaction that could read as harm even there. A pack
  cannot raise `minors` above a mode's maximum (No Upward Leak), so no pack can put children
  into a violent mode.

## Prints
- `prints.v0.json`: `{ "atlas": "prints.png", "cell": 128, "prints": [ { "id", "slots":
  ["top","hoodie","cap","bag","banner"], "descriptors", "variants": { "clean": {"cell": n},
  "fallback": {"cell": n, "descriptors": {...}}, "dystopia": {...} } } ] }`. A variant names a
  cell index in the pack's atlas; `fallback` is required. The base set lives in
  `game/core/content/prints.v0.json` with `prints.png`; a pack's file merges after it (same id
  replaces) and its atlas is bound per pool when any of its prints is in use (one atlas per
  pool; the manager groups agents by atlas, base first).
- Geometry: the torso, hood, cap crown and bag faces get a UV2 rectangle in the builder;
  everything else has UV2 zero. The shader samples the atlas at UV2 offset by the print cell
  and blends over the cloth where the sample's alpha is set. The cell index rides in
  `COLOR.a` (0 = no print); the tints in `COLOR.rgb` are three hues (skin, top, bottom) that
  the fragment shader turns into colours through a small palette LUT, so a pool's eight
  profiles become hundreds of looks with no extra draw calls.
- The three base sheets come from `tools/prints/build_atlas.py`, deterministic, committed
  with a CI diff check like the proving ground: `clean` rasterises a chosen list of emoji
  code points from Noto Emoji (monochrome glyphs tinted by the shader; no copyrighted colour
  emoji art), `gritty` composes invented brand marks (wordmarks in a few open fonts already
  in the repo, simple shapes, satirical names generated from word lists, nothing that reads
  as a real brand or a studio parody), `dystopia` reuses the gritty composer with a harsher
  palette, skulls, glitch bars and corp seals. The validator rejects a variant whose cell is
  outside the atlas.
- The gang's colours: `factions.v0.json` `look` gains `print`, drawn on the crew's tops and the
  leader's cap, so the Double Cross wears its mark; a faction's print is a normal print with
  variants (a paint-splat emoji in clean).

## LODs
- `CharacterMesh.build(profile, pose, skinned, lod)`: LOD0 as today; LOD1 drops eyes, brows,
  mouth, glasses frames and beard geometry (beard becomes a face tint), lower-segment
  primitives, hat and hair merged into one cap; LOD2 eleven boxes. All three share the bone
  pivots so the walk shader and the skeleton pose any of them. Budgets as tests: LOD0 ≤ 1,700,
  LOD1 ≤ 500, LOD2 ≤ 100 on the heaviest profile (long hair, long coat, backpack, headphones).
- Ranges 0–60 m, 60–150 m, 150–350 m through `MapPack.LOD_FADE_M` fading; the player's own body
  is always LOD0. Each pedestrian pool becomes three MultiMeshInstance3D with the LOD's range;
  an agent is written into all three with the same transform (hidden ranges cost nothing).
  Officers and gang members, being rigged actors, switch their mesh instance by distance in
  `CharacterRig`.

## Creator pages
- Five pages on the shoulder buttons, shown as tabs in the menu theme; each page holds its
  rows, the preview stays, randomise and presets stay on every page. The Body page opens with
  the body row; the Clothes page has the print picker, which shows the current mode's variant
  of each print. `docs/controls.md` updated.

## Profile migration
- New fields have index 0 as "none" or the previous look and `body` defaults to `a`, so
  `normalise` on an old dictionary reproduces the old body exactly; `CharacterStore` rewrites
  the file after a load that filled defaults. A test loads a profile saved before this change
  and compares the built mesh's vertex count and AABB with the old builder's.

## Decisions for the human
- The emoji font for the clean sheet: Noto Emoji is proposed (SIL Open Font License 1.1; the
  glyphs are rendered into our atlas at build time and the font itself is not shipped). AGENTS.md
  asks before choosing a licence, so: accept the OFL attribution in LICENSE-ASSETS and the base
  manifest, or use a hand-drawn glyph set with no third-party font.
- The population split per mode: proposed base `a` 0.5, `b` 0.5, and in clean `child` 0.12
  of spawns (adults scaled down to fit); a pack overrides it.
- Whether officers and gang members get both bodies in this pass (proposed: yes, the officer
  and member spawners pick from the same split) or stay as they are until a character pack
  weights them.
