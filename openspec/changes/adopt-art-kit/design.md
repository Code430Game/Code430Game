# Design: Adopting the Quaternius kit

## Licensing (checked 2026-10-10)
- The downloads are public Google Drive folders (and itch.io pages) linked from quaternius.com.
  The site is GitHub Pages, `Quaternius/quaternius.github.io`.
- Each download carries a `License.txt` that reads "CC0 1.0 Universal (CC0 1.0) Public Domain
  Dedication". For example, Ultimate Modular Women (April 2022, Drive folder
  `1720N9IGyQHXYvtvZJzazhxtTTlz-y2Vf`). The pack pages and itch.io pages say CC0 too.
- `quaternius.com/license.html`, the Quaternius Asset License v1.0, was added on 2026-08-28 (commit
  "new kit, added license"). It forbids redistributing the assets standalone, but section 7 says
  it does not apply retroactively, and a CC0 dedication can't be revoked.
- **Rule:** take a pack only when its own downloaded `License.txt` says CC0, and keep that file,
  the link and the download date in the pack folder. Check each pack, the Downtown City MegaKit
  (May 2026) included, at download time. Anything under the QAL stays out: it can't sit in an
  open repo as files anyone can copy.

## Sizes
- Download sizes (all formats): Downtown City MegaKit 223 MB (free tier), Universal Base
  Characters 122 MB, Stylized Nature MegaKit 99 MB, Ultimate Gun Pack 7 MB. The modular men and
  women, Cars and Simple Buildings are smaller and older.
- We commit only the glTF models in use, as `.glb` with shared palette textures; about 40–80 MB
  across all stages. The repo is about 38 MB today. No Git LFS: its free bandwidth quota would be
  eaten by clones. The CI size budget catches growth, and the files are picked and converted
  once, not re-saved.

## Assembly
- **Vehicles (built 2026-10-10):** `tools/vehicle_kit/build_vehicles.py` runs in Blender over
  `recipes.json`. It takes the unmodified sources from `art/quaternius/cars`, swaps the kit
  wheels (1,680 triangles a car) for 16-sided ones named `Wheel_FL` and so on, renames the body
  paint `Paint` (accents `PaintAccent`), scales to the recipe's length and exports to
  `game/assets/vehicles/<id>.glb`. Derived vehicles keep the SUV's cab (cut behind the front
  doors, or behind the rear doors for the pickup, the cut capped) and add a bevelled box or a
  bed with wheel arches cut by a boolean; every number is in the recipe so they can be nudged
  without opening Blender. The measured dims go into the catalogue (`apply_dims.py`).
  `kit_vehicle.gd` rebuilds a model into VehicleMesh's four surfaces (paint white so the tint
  shows, the rest in the kit colours, lights on their own surfaces), so traffic, parked cars
  and the player's car need no other change; LOD1 stays the generated body.
- **Where files live:** unmodified sources in `art/<source>/<pack>/` (outside the Godot
  project, so they aren't imported or exported), built models in `game/assets/`.
- **People:** a kit character is a skeleton plus part meshes (body, head, hair, outfit pieces)
  skinned to it. The profile names a part per slot and colours per material slot. The crowd's
  MultiMesh needs one mesh per pool: the parts are merged into one mesh per pool look at load,
  with bone indices in a custom channel for the walk shader (as `CharacterMesh` does today). The
  shader's pivot array grows to the kit skeleton's bone count, with a cap of about 24 bones;
  extra bones fold into their parents for the crowd.
- **Buildings:** a facade is split into bays the kit's wall-piece width (about 2–4 m) wide and
  floors the kit's storey height; each bay gets a piece (window, blank, door, shop) by rules.
  Corners get corner pieces, and roofs are kit roof pieces or our generated roof on the kit
  palette.

## Open questions
1. Is a stylised low-poly look the final direction for the base game? (The human: "I think its
   realistic enough for me.")
2. Children: decimate Universal Base Characters' teen bodies, or scale the modular bodies?
