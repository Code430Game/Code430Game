# vehicle_kit

Builds the game's vehicles (`game/assets/vehicles/*.glb`) from the Quaternius Cars Pack in
`art/quaternius/cars`. The sources are never edited; every change is a number in
`recipes.json`, so anyone can rebuild the same models.

```sh
scripts/build-vehicles.sh             # every recipe (needs Blender 4.2 or later)
scripts/build-vehicles.sh ambulance   # just one
```

It writes the models, copies their measured dims (length, wheelbase, track, wheel radius,
overhang) into `game/actors/vehicles/vehicles.v0.json`, and renders
`build/vehicle_kit/lineup.png` and `lineup-rear.png` to look at. Commit the `.glb` files and
the catalogue change together; open the game once (or run `scripts/ci-local.sh`) so Godot
re-imports them.

## Recipes
Lengths are in the source model's frame before scaling: front is -y, up is +z, the kit SUV is
4.2 m long with its B-pillar near y 0.22 and the roof at z 1.5.

- `source`, `paint` (the kit material the game tints), `accent` (a darker shade of the tint),
  `length_m` (the built length).
- `derive: "box"` (ambulance, van, box truck): `cab.cut_y` (where the SUV is cut),
  `cab.scale_y` (below 1 squashes the cab forward), `cab.scale_z` (above 1 makes it taller),
  `box` (`y0`, `y1`, `width`, `z0` bottom, `z1` roof, `bevel`, `skirt_h`, `stripe` band,
  `box_paint`), `rear_axle_y`, `windows`, `curb_door`, `beacons`, `roller_door`, `chassis`.
- `derive: "pickup"`: `cab.cut_y` behind the rear doors, `bed` (`y1`, `floor_z`, `top_z`,
  `wall`, `skirt_z`), `rear_axle_y`.

## What the game expects
One `Body` mesh and four wheel meshes (`Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR`, origin
at the hub), front towards -Z, wheels on y = 0. Materials: `Paint`/`PaintAccent` (tinted),
`Headlights`, `TailLights` (glow at night), anything else drawn in its own colour.
`game/actors/vehicles/kit_vehicle.gd` reads them.

New sources go in `art/<source>/<pack>/` with a `SOURCE.md` (licence, links, date, sha256 of
every file); `scripts/check-third-party.sh` checks it.
