# Change: Steal and fly the helicopter

**Status: proposed 2026-10-07 (human: "I am surprised the heli pad is so far away. I will need to search it out to test stealing it… can I steal it yet?"; then "Yes, I think we should be able to steal the helicopter. :)"). Approved to build straight after.**

## Why
The police helicopter is the most visible thing in a chase, and the player can't touch it:
- it's AI only, with no seat;
- when it lands at its pad it's freed (`police_manager._on_helicopter_landed`);
- the pad (the pack's one helipad, around x -939, z -1009) is empty.

Being able to steal it and fly over the city is the kind of thing a crime sandbox should let
you do.

## What Changes
- **A helicopter waits on the pad.**
  - While the police helicopter is idle, it sits on its helipad, parked, rotors still.
  - When it's called out, it lifts off from there, as now. When it lands, it parks again
    instead of being freed.
  - The pad's place in the map legend says it's there.
- **Getting in.**
  - Walk up to it and press get in (Y / E), the same as taking a car.
  - Taking the police helicopter is a crime: `aircraft_theft`, two stars at once, always
    seen.
  - While the player has it, the police have no air unit. A new one is due back at the pad
    after a configured time, unless the player still has it.
- **Flying: arcade, steady, one-handed on the left stick.** In a new `fly` context in
  `controls.json`, shown in the Controls tab and `docs/controls.md`:

  | Control | Pad | Keyboard |
  |---|---|---|
  | move forward, back and sideways (it banks and pitches to move) | left stick | W A S D |
  | climb / descend | RT / LT | Space / Ctrl |
  | turn left / right | LB / RB | Q / E |
  | look | right stick | mouse |
  | get out | Y | F |

  - Letting go holds height and position and levels out.
  - It has a top speed, a ceiling, and a soft boundary at the district edge.
  - Tunables go in `helicopter_flight.json`.
- **Landing and getting out.**
  - It lands on anything flat and solid: ground, decks, roofs, parking lots.
  - Getting out is only allowed when landed or hovering within 2 m of a surface. Otherwise get
    out does nothing and a short hint says "Land first".
  - A parked stolen helicopter stays where it was left.
- **Hitting things.** Rotor or body contact with buildings, decks or the ground faster than a
  threshold, by tone (outcome data, not mode ids, the same as the other outcomes):
  - gritty and dystopia: hard hits damage it, and enough damage makes it auto-rotate down to
    a heavy landing that leaves it disabled;
  - clean: it bounces off and auto-lands gently, and is never destroyed.

  No explosions in this change.
- **The chase with the player in the air.**
  - Ground units see an aircraft from further away (a separate sight range, default 150 m).
  - Distance and height are how to escape: fly beyond their sight for the usual lose time.
  - The seen badge and the minimap work as they do now.
  - If the player lands and gets out, the normal rules apply.
- **Camera and HUD.** A chase camera behind and above, which pulls back with speed. A small
  altitude readout beside the speed line. The minimap is the same.
- **Streaming.** The streamer anchors on the helicopter like the car. Its look-ahead and the
  chunk tier reach scale with speed and height, so the city ahead is built in time; the deck
  preset caps how far that goes.
- **Not in this change:**
  - weapons on the helicopter;
  - other aircraft;
  - flyable helicopters elsewhere (hospital pads);
  - passengers;
  - co-op seats for others. The pilot owns it, like a driven car.

## Co-op authority
The helicopter is a vehicle like the cars:
- the peer flying it owns its body, and its state goes out through the existing vehicle sync;
- the host owns the parked or AI police helicopter;
- if the pilot leaves, it is parked where it is (landed) or auto-lands, and returns to host
  ownership.

## Tone
- Flying is allowed in every tone.
- Crash outcomes come from data (`outcomes.aircraft` in the mode files).
- Clean never destroys it.

## Impact
- Affected specs: `vehicles` (ADDED: Flyable Helicopter).
- Affected code:
  - `game/actors/police/helicopter.gd` and `police_manager.gd` (parked on the pad, stolen
    state, return timer);
  - new `game/actors/vehicles/flyable_helicopter.gd` (flight model) and
    `helicopter_flight.json`;
  - `game/actors/player/player.gd` (entering and leaving an aircraft);
  - `chase_camera.gd` (an aircraft mode);
  - `game/core/input/controls.json`, `project.godot`, `docs/controls.md`;
  - `wanted.gd` and `police_config.json` (`aircraft_theft`, aircraft sight);
  - the mode files and tone schema (`outcomes.aircraft`);
  - `chunk_streamer.gd` (anchor look-ahead by speed and height);
  - `game/core/net/` (vehicle sync for the helicopter);
  - `play_testbed.gd` (small: a `--fly` start flag for screenshots and tests);
  - tests.
- Performance: flying high shows more of the city at once. Deck benchmark while flying over
  downtown, with a target within the existing budget. If not, the deck preset caps the height
  for LOD reach.
