# Change: Radio per car

**Status: proposed 2026-10-06 from the backlog (human, 2026-10-04, Deck drive for `add-car-radio`).**

## Why
Today the radio station follows the player into any car. A car of your own should keep the
station you left it on, and a taken car should be playing whatever its owner had on.

## What Changes
- Each drivable car carries a `radio_station` (an id from the station list, or off).
- The player's first car starts on the player's last chosen station; changing station
  changes that car's station.
- A taken traffic or parked car gets a random station (seeded by the car), sometimes off.
  Ambulances and patrol cars start on Chatter AM or off.
- Getting out and back in keeps the car's station. Co-op: the station rides with the car's
  existing snapshot.
- **Not in this change:** new stations, a radio dial UI.

## Impact
- Affected specs: `audio` (ADDED: Station Per Car).
- Affected code: `game/audio/` radio player (`add-car-radio`), `placeholder_car.gd` (field), the
  testbed's enter and exit paths, `traffic_manager.take_car`, parked cars, co-op car sync; tests.
- No dependency on other open changes.
