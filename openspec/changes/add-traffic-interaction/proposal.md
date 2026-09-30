# Change: Traffic that stops for you, recovers after a hit, and can be taken

**Status: proposed 2026-09-30, from the human's Deck drive report ("make the other cars cars").**

## Why
Traffic works as a simulation but not as something to be in the middle of. Cars do not
see the player: they drive through a person on foot, they pile into a stopped player car
until it is buried, and a hit car keeps its physics body until the player is 380 m away,
so after a few crashes the body pool runs dry and new cars are ghosts you walk through.
A traffic car also cannot be taken, which the genre expects.

## What Changes
- **Players are obstacles.** Each agent treats every player body (car or on foot) that is
  ahead in its lane corridor as a car to keep headway from, so traffic stops behind a
  stopped player and does not run a pedestrian down.
- **Hit cars queue and recover.** A retired (hit) car stays an obstacle for the cars
  behind it, so they queue instead of stacking. After the physics window it looks for a
  lane within reach and, when it is near one and roughly aligned, resumes driving;
  otherwise it stays put and releases its physics body once no player is near.
- **Body pool hygiene.** Bodies are released from retired cars beyond the body radius,
  and traffic cars carry a physics layer the on-foot player collides with.
- **Taking a traffic car.** Pressing interact next to a traffic car with no player
  vehicle nearer converts it into a drivable placeholder car in the traffic car's colour
  and puts the player in it. The agent is removed; the taken car is an ordinary vehicle.
- **Not in this change:** occupants, damage, police response, honking, lane changes,
  overtaking, tone-mode content.

## Impact
- Affected specs: `traffic` (new requirements; add-traffic is still open, so no MODIFIED).
- Affected code: `game/world/traffic/traffic_manager.gd`, `traffic_agent.gd`,
  `traffic_car.gd/.tscn`, `traffic_config.json`, `game/actors/player/player.gd`,
  `game/scenes/play_testbed.gd`, tests.
- Performance: obstacle checks are per agent within lookahead of a player only; expected
  well under 1 ms on the Deck. Measured after.
