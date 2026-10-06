# Change: Fire trucks answer fires

**Status: proposed 2026-10-05 (human: "fire stations and trucks, these should respond ... if fires happen (not yet but one day)"). Parked until fire exists; this change brings the smallest fire it needs. Builds on `add-emergency-services` (the fire stations) and shares the dispatch code with `add-ambulance-response`.**

## Why
The pack has two fire stations, Ottawa Fire Station 11 and 13, that do nothing. The truck
wants something to answer, so this change brings a small, contained fire as well.

## What Changes
- **Fire.** A `Fires` node holds point fires: particle flames, smoke, a flickering orange
  omni light and a crackle voice. Fires are started by:
  - a car taking a crash above a high impulse threshold (it smokes, then burns);
  - the testbed's `--fire=x,z` flag.
  A fire burns down by itself after a few minutes and never spreads; spreading and burning
  buildings are out of scope. Walkers keep away from it, and standing in it hurts the player.
- **Trucks.** The nearest fire station sends one truck per fire, at most two at once. It
  uses the ambulance dispatch, route, lights and siren with a long red body. On scene a
  firefighter sprays: a water particle arc that shrinks the fire to nothing. Then the truck
  returns.
- **Tone.**
  - **clean:** wrecks give off smoke but never flames; the truck still comes and hoses them.
  - **gritty:** flames as above.
  - **dystopia:** a foam drone flies from the station instead of a truck.
- **Not in this change:** building fires, spread, explosions, the player driving the truck.

## Co-op authority
The host owns fires and trucks.

## Impact
- Affected specs: `emergency-services` (ADDED: Fire Response).
- Affected code: `game/world/fire/fires.gd` (new), the vehicle crash hook, the truck
  catalogue entry, the shared dispatch in `game/actors/emergency/`, the testbed; tests.
- Performance: particles capped per fire (two fires on the Deck preset). Deck benchmark
  with two fires and two trucks.
