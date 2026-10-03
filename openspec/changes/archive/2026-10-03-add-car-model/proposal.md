# Change: Procedural car body for the player and traffic

**Status: proposed 2026-09-30 (queue item: car model and handling; the model half).**

## Why
Every car is a flat red or coloured box. A low-poly body with a cabin, wheel wells, lights
and wheels reads as a car at Deck distances, costs almost nothing, and gives traffic colour
variety a shape to sit on. No art assets are needed: the mesh is built from parameters so the
same generator can later produce a few body types (sedan, hatch, van) and tone-mode liveries.

## What Changes
- **CarMesh** builds an ArrayMesh from a body profile: lower body, cabin with raked
  windscreen and rear glass, wheel arches, head and tail lights as vertex-coloured quads.
  Body vertices are white so a MultiMesh instance colour or a material tint paints them;
  glass, trim and lights keep their own colours.
- **Player car** uses the mesh on its body node with its own tint; wheels become cylinders
  with a dark tyre and a lighter hub.
- **Traffic** draws the same mesh through its MultiMesh with per-instance colour; one shared
  mesh keeps draw calls where they are.
- **Taken cars** keep their traffic colour.
- **Not in this change:** handling changes, damage, multiple body types, interiors, drivers.

## Impact
- Affected specs: `vehicles` (new).
- Affected code: `game/actors/vehicles/car_mesh.gd` (new), `placeholder_car.tscn`,
  `traffic_manager.gd`, tests.
- Performance: one mesh of a few hundred triangles; traffic draw calls unchanged. Deck GPU
  measured before and after.
