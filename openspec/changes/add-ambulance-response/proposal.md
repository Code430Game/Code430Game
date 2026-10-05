# Change: Ambulances answer the injured

**Status: proposed 2026-10-05 (human: "hospitals and fire stations and trucks, these should respond if people are injured"). Builds on `add-emergency-services`, which imports the hospitals and ambulance posts.**

## Why
Today someone knocked down lies there until they are cleared away after `remove_after_s`.
Nothing in the city notices. An ambulance arriving with its lights on makes a hit feel like
it happened somewhere, and it uses the hospitals and ambulance posts already in the pack.

## What Changes
- **Calls.** A downed pedestrian (car, weapon or crash) files a call after a short delay.
  Calls near each other merge into one. At most two ambulances are out at once; more calls
  wait in a queue.
- **Dispatch.** The ambulance leaves from the nearest ambulance post or hospital that is
  within reach on the road graph. It drives there with lights and siren, using the police
  A* route and the traffic rules the police cars use (it pulls through red lights slowly).
  When neither place is close, it spawns out of view on the way in, as police cars do.
- **On scene.** It stops beside the person, and two paramedics get out and kneel for a few
  seconds. Then, by tone:
  - **clean:** the person gets up with a bandage and walks off;
  - **gritty:** they are lifted onto a stretcher and loaded in;
  - **dystopia:** a medical drone lifts them away.
  The ambulance drives back to its station and is freed out of view.
- **Bodies wait for help.** A downed person with a call open is not cleared until the
  ambulance has dealt with them, or until a hard timeout runs out.
- **Wanted level.** Hitting a paramedic or the ambulance counts as an offence, through the
  existing wanted rules.
- **Map.** Ambulances on the way show on the minimap as a small cross.
- **Not in this change:** the player driving the ambulance, paramedic missions, healing the
  player, hospital interiors.

## Co-op authority
The host owns calls and ambulances and replicates them like police cars.

## Impact
- Affected specs: `emergency-services` (ADDED: Ambulance Response).
- Affected code: `game/actors/emergency/ambulance_manager.gd` (new), the ambulance body in
  the vehicle catalogue, `pedestrian_manager.gd` (a `downed` signal, hold-until-helped),
  the testbed wiring, the minimap; tests.
- Performance: at most two extra cars and four extra walkers. Deck benchmark with two calls
  open.
