# Change: Police pursuit you can read and escape

**Status: proposed 2026-10-06 from the human's Deck session (2026-10-06): "the cops are fun"; "I still think it might be impossible to drive away from the copter"; "I wonder if there's another mechanic we can use to indicate to the player that the helicopter or any police can see you. An outright find cover might be too much but if we indicate to the user when they are not seen by the police it might achieve the same thing but better ... maybe a badge for seen and a blinking badge for hidden?"; "it will be easier to understand where/when the helicopter is near since it's easier to see the spotlight when it turns on at night." Approved to build straight after (human, 2026-10-06).**

## Why
The chase works, but the player can't read it:
- **Nothing shows whether police can see you.** The wanted level only drops after a stretch
  unseen (`lose_s`: 12, 18 or 25 s at one to three stars). Hiding works, but nothing on screen
  says so, and nothing says when you've been spotted again.
- **The helicopter can't be outrun.** It flies straight at 45 m/s (about 160 km/h), faster
  than any car, and sees 150 m. Its only weakness is cover, and the player can't tell when
  cover is working.
- **Thick tree cover doesn't hide you,** though `add-police-helicopter` said it would. Only
  street-tree trunks have collision, and the sight ray passes through canopies.
- **At night the searchlight shows where the helicopter is looking; by day there's no cue.**
- **Empty patrol cars keep driving.** When an officer gets out, the car is only marked
  `officer_out` (`police_manager.gd:295`). `_drive` never checks the mark, so the empty car
  keeps chasing once the player moves.

## What Changes
- **Seen badge.** An eye badge beside the wanted stars, shown only while wanted:
  - **Seen:** the eye is solid. A small mark beside it names who has you: a helicopter, ground
    units, or both.
  - **Hidden:** the eye is closed or hollow and blinks. A ring around it fills as the time
    unseen approaches what the current stars need (`unseen_s / lose_s[stars]`).
  - **Spotted again:** the eye snaps back to solid and the ring empties.

  There's no text. The stars stay as they are; the badge is separate, so the design isn't
  GTA's grey-flashing stars.
- **Minimap states.** A police marker is solid while that unit sees the player and hollow
  otherwise. The helicopter's ring is dashed while it searches where it lost the player.
- **The helicopter can be outrun.**
  - Its speed drops below a fast car's top speed (default 35 m/s, about 126 km/h).
  - In the open, a player who stays beyond its sight range for its lost time is lost, the
    same as under cover.
  - Its constants (`SPEED_MPS`, `SIGHT_M`, `LOST_S`, the search radius, the cruise and orbit
    heights) move to `police_config.json`.
- **Tree canopy is cover.** The helicopter's sight ray counts dense canopy as blocking: a
  sight query against the vegetation's canopy volumes, not physics bodies, so nothing
  collides with leaves. Thin rows of street trees don't count; parks and dense groups do. The
  threshold is in config.
- **Empty patrol cars park.** A patrol car whose officer is out holds still with its handbrake
  on until the officer gets back in or the chase ends.
- **Daytime cue: decided by play.** At night the searchlight stays as the cue. By day the
  badge is the cue in this change. If the human's play finds the helicopter still hard to
  place by day, a follow-up adds one (a ground shadow or the rotor sound placed in space).
- **Not in this change:** shooting or fighting officers (its own proposal), roadblocks,
  changing how stars are earned, an on-screen "find cover" hint.

## Co-op authority
The badge and the minimap states are local UI drawn from the local player's wanted state,
which is host-local in this pass, as in `add-police`. The helicopter, patrol cars and their
sight run on the host, as now.

## Tone
Unchanged: the same chase in every tone. The badge has no text. Its colours come from the HUD
accent (`ContentMode.hud_accent`, from `add-weapon-selector`).

## Impact
- Affected specs: `police` (ADDED: Readable Pursuit).
- Affected code:
  - `game/actors/police/wanted.gd` (seen-by and hidden progress);
  - `helicopter.gd` (speed, sight and canopy, constants to config);
  - `police_manager.gd` (parked empty cars, per-unit sight for markers);
  - `police_config.json`;
  - `game/world/vegetation/` (a canopy query);
  - `game/ui/hud/` (a new `seen_badge.gd`);
  - `game/ui/map/minimap.gd` (hollow and dashed markers);
  - `game/scenes/play_testbed.gd` (a small edit);
  - tests.
- Performance: one extra ray per police unit per sight check, and the canopy query only on
  the helicopter's sight ray. Nothing per frame while not wanted.
