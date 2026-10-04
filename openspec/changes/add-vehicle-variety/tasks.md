## 1. Catalogue
- [x] 1.1 `vehicles.schema.v0.json`, base `vehicles.v0.json` with nine entries, `VehicleCatalogue` autoload with merge and `pick_for_spawn`; `pack_tools` validates pack copies; tests; done 2026-10-04 (the map pack's `vehicles.v0.json`, if any, merges at load: there is no general pack loader yet)

## 2. Generator
- [x] 2.1 `trim_sheet.gd`: generated atlas; test on determinism and cell colours
- [x] 2.2 `vehicle_mesh.gd`: parametric profile per class, LOD0 details, LOD1; tests on triangle budgets per class, outward faces, surface colour split, bounds matching `dims`; done 2026-10-04: every face carries its own outward normal (flat shading) and the test checks each triangle's winding against it, plus exact checks on side panels, roof and underside; LOD0 410–430 triangles with wheels, LOD1 145–200
- [x] 2.3 Mac screenshots: a lineup of all nine classes at LOD0 and LOD1 side by side, day and night; done 2026-10-04 with `scenes/vehicle_lineup.tscn` (`--angle=front|side|rear`, `--night`, `--screenshot=`): front, side, rear and night shots shared with the human

## 3. Traffic
- [x] 3.1 Per-class, per-LOD MultiMeshes, LOD pick by distance, spawn weights by road group and hour, pooled body box and mass from the class; tests on class mix at noon and at 22:00 and on LOD assignment; done 2026-10-04: lane first (road weights), then the vehicle by road group and hour; bus lanes take only buses; MultiMeshes grow when a class is busier than its estimate, so no car goes undrawn; LOD distance from the preset (`vehicle_lod0_m`, 60 m deck, 110 m high); `--bus-share` now sets the bus's catalogue weight
- [x] 3.2 Snapshot stride 7 with class index; mirror client rebuilds classes; sync tests; done 2026-10-04: colour index is into the vehicle's own palette; an unknown vehicle index falls back to the sedan

- [ ] 3.3 Immovable traffic fix, part 1: `scenes/traffic_hit_lab.tscn` (the player's car rear-ends a stopped traffic car at 50 km/h; the player's car wedged between two traffic cars that close on it), logging speeds and the peak speed of every body; confirm the cause from the numbers, and record **before** on the Mac
- [ ] 3.4 Immovable traffic fix, part 2: a sensor on traffic bodies switches them to dynamic before a closing vehicle touches them, with the agent's velocity and the class's mass; separation speed capped; tests: rear-end shares momentum, the wedge never exceeds the cap, a frozen traffic body never meets a vehicle in contact; record **after** with the same camera

## 4. Player car
- [ ] 4.1 `apply_entry` on the placeholder car (wheels, mass, tunables, mesh); taking a traffic car keeps its class; `--car=<id>`; remote replicas build the class; tests
- [ ] 4.2 Mac drive: hatchback, SUV and box truck feel different on the Queensway ramp

## 5. Verification
- [ ] 5.1 Deck benchmark on the usual route with 150 agents: frame avg and p99, GPU, draw calls quoted against the bus round's 413; no regression past budget
- [ ] 5.2 **Stop: human drives a few classes on the Deck and watches the traffic mix downtown and on the 417**
