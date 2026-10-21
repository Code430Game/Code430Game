# Change: World tab (weather, time) and "Go to" a place

**Status: proposed 2026-10-21 after the Deck answers: no rain or snow came in a session, the
flyable helicopter was too far to find, and the gang's turf was hard to reach. The maintainer
wants fewer checks answered from memory, and testers will need the same shortcuts.**

## Why
Weather walks a table that is rarely wet within one session (clear lasts 15 to 40 minutes and
is followed by clear 60% of the time). Night needs `--time=22` or a long wait. The helipad is
over a kilometre from the start, and so is the Double Cross turf. Command-line flags cover all
of this on the Mac, but nobody can pass flags from Steam's Game Mode, and testers won't.

## What Changes
- **A World tab in the pause menu**, after Options:
  - **Weather:** Auto (the table, as now), Clear, Overcast, Rain, Snow, Fog. Picking one blends
    to it over its usual transition and holds it; Auto lets the table walk again from there.
  - **Time:** Auto (the clock runs), or a fixed hour (06:00, 09:00, 12:00, 17:00, 20:00,
    22:00, 02:00). A fixed hour sets the clock and stops it; Auto starts it from that hour.
  - **Day length:** the minutes a game day takes (as `--day-minutes`), a few steps.
  - Snow ignores `snow_hours` when picked here.
- **"Go to" in the map legend.**
  - On a place in a kind's list (garage, helipad, hospital, police station...), Y "Go to"
    moves the player there on foot, beside it, facing the street.
  - Turfs get a legend kind of their own ("Gang turf"), so "Go to" reaches them too.
  - Refused while wanted (stars above 0), with a line saying why, so it can't end a chase.
- **Co-op.** Weather and time are host-owned already: on a guest the World tab shows the
  host's choice, greyed out. "Go to" is per player and works for guests.
- **The play log** (`add-play-log`, if built first) logs each pick, so a check knows the
  weather or the hour was chosen, not waited for.

## Impact
- Affected specs: `menus` (ADDED: World Tab), `wayfinding` (ADDED: Go To A Place).
- Affected code:
  - `game/ui/pause/pause_menu.gd` (the tab);
  - `game/world/sky/weather.gd` (hold a picked state, release to Auto);
  - `game/world/sky/day_night.gd` (fixed hour, stopped clock);
  - `game/ui/map/map_legend.gd` and `place_icons.json` (Go to, the turf kind);
  - `game/scenes/play_testbed.gd` (move the player, the wanted rule);
  - `game/core/net/world_sync.gd` (the host's picks);
  - `docs/controls.md`; tests.
