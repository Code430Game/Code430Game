# people_kit

Builds the game's people (`game/assets/people/men.glb`, `women.glb` and `people.json`) from the
Quaternius Ultimate Modular Men and Women in `art/quaternius/modular_men` and `modular_women`.
The sources are never edited; every choice is in `recipes.json`, so anyone can rebuild the
same models.

```sh
scripts/build-people.sh          # both packs (needs Blender 4.2 or later)
scripts/build-people.sh women    # just one
```

It writes the models and `people.json`, and renders `build/people_kit/lineup-men.png` and
`lineup-women.png`: row 1 is every outfit, row 2 every hair style, beard and hat. Tinted parts
show in stand-in colours there (blue top, yellow accent, grey bottom, brown shoes). Commit the
`.glb` files and `people.json` together; open the game once (or run `scripts/ci-local.sh`) so
Godot re-imports them.

## How a kit person becomes a game person
The game walks people on its own eleven-bone rig with a procedural walk that also runs in the
crowd's shader (`CharacterMesh`, `pedestrian_walk.gdshader`), so the kit's 62-bone skeleton and
animations are not used. The script lowers the kit's T-pose arms, bakes that pose, and gives
every vertex the one rig bone that carries most of its weight (fingers go to the forearm, the
foot to the shin). The bone index travels in the vertex colour. Parts over their budget are
decimated, then everything is scaled so a man's head is `height_m` tall.

## Recipes
Mesh and material names are the ones in the master `.blend` files (open one in Blender to look,
or see the probe output in the pull request that added this).

- `height_m`: the top of a man's head; women keep the kit's size against men.
- `arm_hang_deg`: how far the arms come down from the T-pose (90 is straight down).
- `budget`: most triangles per part (`under` is the hair below a hat).
- `beard_region`: splits one kit mesh's hair into beard (low and in front) and the rest.
- Per pack: `face` (`from` a head mesh, `roles` from kit material to role), and the lists the
  creator steps through, in order: `hair`, `beard`, `hat` (each `name`, `from`, `materials`,
  and `region`, `role` or `under` where needed) and `outfits` (`top`, `legs`, `feet` meshes and
  `tint`: kit material to `Top`, `Accent`, `Bottom` or `Shoes`). Each list must be as long in
  both packs; a choice with no `from` draws nothing (bald, no beard).
- Roles the game paints: `Skin`, `Hair`, `Eye`, `Stubble`, `Top`, `Accent` (the jacket
  colour), `Bottom`, `Shoes`. Every other kit material keeps its colour.
- The outfit named `uniform` is for roles (police) and never drawn at random; roles find
  `uniform`, `worker` and `punk` by name.
