# Design: vehicle catalogue and generator

## Catalogue
- `vehicles.v0.json`: `{"schema_version": 0, "vehicles": [...]}`. Entry fields: `id`,
  `name`, `body_class` (one of the generator's classes), `dims` (`length_m`, `width_m`,
  `height_m`, `wheelbase_m`, `track_m`, `wheel_radius_m`, `front_overhang_m`, `cabin_start_m`,
  `roof_length_m`, `bed_length_m` or `box_length_m` where the class uses them), `mass_kg`,
  `engine_force`, `brake_force`, `grip`, `top_speed_kph`, `steer_max_rad`, `seats`,
  `colors` (list of RGB), `spawn` (`weight`, `roads` {motorway, arterial, local}, `hours`
  list of [from, to, factor]), `descriptors`, `liveries` (`fallback` plus per-mode variants,
  each a palette override, a stripe pattern id and an optional roof sign text).
- Base set: `sedan`, `hatchback`, `coupe`, `suv`, `pickup`, `van`, `box_truck`, `taxi`, `bus`.
  Ids are generic words; names are invented.
- Merge order: base, then packs in load order; same id replaces. `VehicleCatalogue` autoload
  exposes `get(id)`, `ids()`, `pick_for_spawn(road_class, hour, rng)` and the default player id.

## Generator
- `VehicleMesh.build(entry, lod, with_wheels)`; the profile is computed from `dims` rather
  than hard-coded: bonnet height, cabin start, roof length and rear deck or hatch or bed or box
  define the (z, y) side profile per class. Sides are extruded with a skirt inset, and wheel
  wells are cut as rectangular notches in the skirt around each axle with a dark inner face.
- LOD0 adds: front and rear bumpers (boxes with a lower lip), pillars as dark quads over the
  glass band, glass inset 3 cm behind the pillar plane, two mirror boxes on stalks, lights with
  a lens quad from the atlas, a plate quad front and rear, taxi roof sign, cargo box with a
  rear roller door seam, pickup bed with an open top and tailgate.
- LOD1: hull, glass band as vertex colour, head and tail light quads, six-sided wheels.
- Surfaces as today: 0 body (white), 1 dark, 2 headlights, 3 tail lights (brake shader with
  `INSTANCE_CUSTOM.r`). The atlas is bound to surface 0 and 1; surface 0 multiplies vertex
  colour by instance colour by atlas.
- Triangle budgets, enforced by tests: LOD0 sedan, hatchback, coupe, taxi at most 900; SUV,
  pickup, van at most 1100; box truck at most 1300; LOD1 every class at most 260. Wheels are
  12-sided at LOD0 and 6-sided at LOD1. Every triangle faces outward (the existing test).

## Trim sheet
- `TrimSheet.build()` makes a 256 by 256 `ImageTexture` once at startup, deterministic, no
  file on disk: grille bars, plate background with a generic glyph pattern, lens radial, door
  seam line, window tint gradient, check stripe, blank. Cells are 32 px; the generator maps
  each detail quad to its cell.

## Traffic
- `_setup_rendering` builds `MultiMeshInstance3D` per (class, LOD) with `instance_count` from
  the class's share of `max_agents` times two, minimum eight; `_render` assigns each agent to
  LOD0 when within `lod0_m` (60 on deck, 110 on high, in `presets.json`) of the nearest player,
  else LOD1, and writes transform, colour and brake custom data to that MultiMesh.
- Spawn: `pick_for_spawn` multiplies `weight`, the `roads` factor for the lane's road class
  group and the `hours` factor for the clock; the colour comes from the entry's palette.
- Snapshot stride 7: x, y, z, yaw, colour index, kind, class index. Mirror clients rebuild the
  agent's class from the catalogue; an unknown class falls back to `sedan`.
- `TrafficCar.set_box` takes the class dims and `mass_kg`.

## Player car
- The scene keeps `VehicleBody3D` and four `VehicleWheel3D`; `apply_entry(entry)` moves the
  wheels to the wheelbase and track, sets radius, mass, friction slip and the exported
  tunables, and swaps the mesh. The chase camera reads the length for its framing.
- `--car=<id>` on the testbed; the pause menu does not pick cars in this change.

## Decisions for the human
- Eight body classes is the proposal; say if fewer (sedan, hatchback, SUV, van, box truck) is
  enough for the first pass to cut the draw-call cost in half.
- Taxi and box truck liveries carry invented names; confirm no Ottawa in-jokes are wanted
  there before content is authored.

## Immovable traffic fix (folded in 2026-10-04)
- **Cause to confirm with the lab:** `TrafficCar` is frozen kinematic while following and is
  moved by `global_transform =` each frame, so it is infinite-mass to the solver and carries no
  velocity. `body_entered` unfreezes it only after the first contact is solved, which is the
  same timing bug as pedestrians. Two such bodies closing on a car leave the solver no valid
  way to separate them except launching the car.
- **Fix:** as with pedestrians, a slightly larger sensor (`Area3D`, mask 1) on each pooled
  traffic body reports a `VehicleBody3D` closing at more than `hit_min_speed_mps`. The body
  unfreezes before contact with `linear_velocity` set to the agent's (forward times speed) and
  its class mass, and the agent goes to the existing `resting` or hit handling. Traffic cars
  stay solid to the player on foot (layer 1). Closing between traffic bodies themselves is
  left to the agents' headway, as now.
- **Separation cap:** for a short window after an unfreeze, the bodies involved (the player's
  car and the struck traffic cars) clamp their linear speed to `max(speed before contact,
  separation_cap_mps)` (default 25 m/s) in `_integrate_forces` for traffic and in the player
  car's physics step. A wedge can never launch anything, and normal crashes are untouched.
- **Lab:** `scenes/traffic_hit_lab.tscn`, built like `ped_hit_lab`: a rear-end at 50 km/h and
  a wedge (two traffic cars closing on the stationary player car from front and back). It logs
  the player car's speed before and after and the peak speed of every body, prints one
  `traffic-hit:` line per scenario, and is reused by the tests.
