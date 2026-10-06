# Change: Hover cars in the dystopia tone

**Status: proposed 2026-10-05 (human: "I feel like the dystopian could have hover cars that drive like helicopters"). Builds on `add-police-helicopter`, whose flight code it shares.**

## Why
Dystopia swaps the look of things but drives the same as the other tones. A car that lifts
off the road and flies over the traffic makes the tone play differently, and the helicopter
already has most of the flight model.

## What Changes
- **The hover car.** A dystopia catalogue body with glowing pads instead of wheels. It is
  not a `VehicleBody3D`: it is a `RigidBody3D` with a hover spring that holds it about 1 m
  off whatever is below it.
- **Driving.** On the ground it drives like a car: same keys and stick, but softer grip and a
  little drift. Hold the climb control (new action, Space / A on the pad) to rise. The
  descend control (Ctrl / B) lowers it. Off the controls it holds its height. A ceiling of
  60 m keeps it inside the NEAR and MID streaming tiers. Out of fuel or flipped, it settles
  to the ground.
- **Flight.** Pitch and roll follow the stick like the helicopter. It collides with
  buildings, bridges and garages like any body. The chase camera pulls back as it climbs.
- **In the world.**
  - In dystopia, about one car in five of the player's picks is a hover car.
  - Traffic gets some hover cars that follow the lanes at 6–10 m.
  - Police at 2+ stars in dystopia use hover cruisers that can follow you up.
  - Parked hover cars sit on their pads.
- **Not in this change:** sky lanes, landing pads on roofs, other tones.

## Co-op authority
The driving client owns its hover car as with cars now; the host owns traffic and police
hover cars.

## Impact
- Affected specs: `vehicles` (ADDED: Hover Cars In Dystopia).
- Affected code: `game/actors/vehicles/hover_car.gd` (new), the catalogue, `controls.json`
  (climb and descend), the chase camera height, traffic and police spawning for dystopia,
  and the shared flight helper with `helicopter.gd`; tests.
- Performance: a hover spring is one ray per pad. Deck benchmark of a dystopia drive with
  hover traffic.
