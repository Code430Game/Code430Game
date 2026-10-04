# Change: Vehicle catalogue with body classes and LODs

**Status: proposed 2026-10-02 (human: "another pass of the vehicles to create higher quality and more variety"); approved 2026-10-04 with the immovable-traffic-car fix folded in (human: "Lets merge the immovable car bug with the same pr"). The design's open decisions were taken as proposed: eight body classes, and invented livery names with no local in-jokes.**

## Why
Every car on the road is the same 4.3 m sedan hull in eight colours, and the bus is a box.
`CarMesh` already proved the approach (a profile extruded into a hull, white body vertices
tinted per instance, four surfaces so lights and glass keep their colours). This pass makes
that generator parametric, drives it from a data catalogue, and adds the details that make a
silhouette read at Deck distances: wheel wells, bumpers, pillars, window insets, mirrors,
plates. A catalogue also means a pack can add a vehicle with JSON and no art.

## What Changes
- **Catalogue as data.** `docs/pack-format/vehicles.schema.v0.json` and the base set in
  `game/actors/vehicles/vehicles.v0.json`: each entry has an id, a `body_class`, dimensions
  (length, width, height, wheelbase, track, wheel radius, overhangs, cabin position, roof length,
  bed or box length), `mass_kg`, `engine_force`, `brake_force`, `grip` (wheel friction slip),
  `top_speed_kph`, `steer_max_rad`, `seats`, a colour palette, `descriptors` and `liveries` with
  per-mode variants and a required fallback. Packs of any type may ship `vehicles.v0.json`; the
  loader merges after the base set and `pack_tools` validates the file.
- **Body classes.** Eight generated from one `VehicleMesh` generator: sedan, hatchback, coupe,
  SUV, pickup (open bed), van, box truck (cab plus cargo box), and taxi (sedan body with a
  livery and roof sign). The bus stays on `BusMesh` behind a catalogue entry; police and
  emergency bodies are catalogue entries for a later change. Each class has a LOD0 with wheel
  wells cut into the side skirts, bumpers, A/B/C pillars as dark strips, inset glass, mirrors,
  head and tail lights, a plate quad front and rear, and a LOD1 that is the hull, glass band,
  lights and six-sided wheels.
- **Trim sheet.** One 256 by 256 atlas generated at startup from code (grille, plate, lens,
  door seam, window tint, taxi check stripe), shared by every class; UVs are assigned by the
  generator so detail needs no per-model art. Body vertices stay white so instance colour
  tints them through the atlas.
- **Traffic.** One MultiMesh per class per LOD; an agent picks its class at spawn from
  `spawn` weights in the catalogue, scaled by the road class group (motorway, arterial, local)
  and the hour (vans and box trucks by day, taxis in the evening). LOD is chosen per agent per
  frame by distance to the nearest player. Pooled bodies take the class's box and mass.
  Snapshots gain a class index beside the colour index (stride 6 to 7).
- **Player car.** `placeholder_car.tscn` builds from a catalogue entry: mesh, wheel positions
  and radius, mass, engine, brake, grip, steer and top speed, so an SUV wallows and a hatchback
  darts. Taking a traffic car keeps its class and colour. Testbed `--car=<id>` for screenshots
  and benchmarks; the spawn car is the catalogue default.
- **Traffic cars are solid but not immovable (fix, folded in 2026-10-04).** The human saw
  "two cars got pinned and things flew to the other end of the map". Traffic bodies are frozen
  kinematic RigidBody3Ds moved by setting their transform, the same pattern that made
  pedestrians stop cars dead (fixed in `add-pedestrians`). The solver treats a frozen body as
  immovable, and a teleported one carries no velocity, so a car wedged against or between them
  is pushed out with whatever speed resolves the overlap. A hit lab reproduces it first and
  confirms the cause; then traffic bodies near a closing player car switch to dynamic before
  contact (carrying the agent's velocity and the class's mass), so crashes trade momentum
  between two real bodies, and the separation speed is capped so a wedged car can't be flung.
- **Not in this change:** damage deformation, interiors and drivers, motorcycles and
  bicycles, suspension or tyre model changes beyond the exposed tunables, horns and sirens,
  trailers.

## Co-op authority
Unchanged: the driving peer owns its car; the host owns traffic. Class and colour travel in
the traffic snapshot and in the player state (one extra byte) so remote replicas build the
right body.

## Tone
Liveries and wraps are content items: `ContentMode.pick_variant` picks the livery per mode and
descriptors gate it; a taxi company name or an ad wrap on a van is invented, never a real
brand. Body shapes carry no descriptors.

## Impact
- Affected specs: `vehicles` (new requirements), `traffic` (new requirement).
- Affected code: `game/actors/vehicles/vehicle_mesh.gd` (new, replaces `car_mesh.gd`),
  `vehicle_catalogue.gd` (new), `trim_sheet.gd` (new), `vehicles.v0.json` (new),
  `bus_mesh.gd` (catalogue entry), `placeholder_car.gd` and `.tscn` (tunables from data),
  `game/world/traffic/traffic_manager.gd` (per-class MultiMeshes, LOD pick, spawn weights,
  snapshot stride), `traffic_agent.gd` (class index), `traffic_car.gd` (box and mass),
  `traffic_config.json` (colours move to the catalogue; hit tunables), `traffic_car.gd`
  (sensor, dynamic before contact), `game/core/net/world_sync.gd` and
  `player_sync.gd` (class), `game/actors/remote_player.gd`, `game/scenes/play_testbed.gd`
  (`--car=`), `docs/pack-format/vehicles.schema.v0.json`, `tools/pack_tools/validate.py`,
  tests (`test_vehicle_mesh.gd` replaces `test_car_mesh.gd`, traffic and sync tests).
- Performance: MultiMeshes go from 2 to 18 (eight classes plus bus, two LODs), four surfaces
  each, so up to 72 traffic draw calls against 8 today, inside the 413 measured with buses.
  Triangles per car fall for far agents (LOD1). Budgets in `design.md`; Deck measured with
  150 agents on the usual route, draw calls and GPU time quoted.
