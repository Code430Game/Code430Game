# Change: Play log, so the game confirms what happened

**Status: proposed 2026-10-21 from the human, after answering 21 Deck checks from memory: "We
need analytics or something so i dont need to confirm every in game event".**

## Why
About twenty merged changes wait on "the human tries it on the Deck". Most of those checks
ask whether something happened: the ambulance arrived, the gang spawned, rain fell, traffic had
headlights at night. The game knows the answer, but today it's recalled from memory days later
("iirc"). Testers outside the team will make this worse: their reports say what went wrong,
never what worked.

## What Changes
- **Stage 1: a local play log (this change's core).**
  - The game writes one JSON Lines file per session, `user://playlog/<start time>.jsonl`, and
    keeps the last 30 sessions.
  - The first line describes the session: build, pack(s), preset, tone, weather, time of day,
    co-op role. Then one line per event: time, kind, place (x, z), and a few fields.
  - Systems call one function, `PlayLog.event(kind, fields)`. Kinds are listed in
    `game/core/playlog/events.json` with their fields, so a typo fails a test.
  - First events cover the open Deck checks:
    - ambulance dispatched and arrived;
    - busted and wasted;
    - wanted level and police helicopter (spawned, sight lost, chase lost);
    - gang spawned and fight started;
    - weather changed;
    - a vehicle entered (kind, and whether it's a helicopter);
    - a garage entered;
    - radio station per car;
    - map legend place picked;
    - pack enabled or disabled;
    - at night, how many traffic cars near the player have their lights on.
  - Once a minute, a sample of the player's position and frame times, so a log also shows
    where the player went and how it ran.
  - No network. Nothing personal: no account, no hardware id, no free text.
- **A check tool for the Deck.**
  - `scripts/deck-playlog.sh` copies the logs from the Deck over SSH.
  - `python -m playlog check` matches them against checks written beside each Deck task:
    `<!-- playlog: ambulance_arrived -->` in `tasks.md` names the event (or a small expression
    over events) that confirms it.
  - It prints each open Deck task as seen (with the session and time) or not seen. With
    `--tick` it ticks the seen ones and notes the evidence, the way the human's answers are
    noted today.
  - Questions of feel ("is it fun and fair", "does it read as a town") stay with the human.
    Each such task is split so the factual half can be confirmed by the log.
- **Stage 2: testers (after stage 1, separate tasks).**
  - A setting, off by default: "Share play logs with bug reports". When on, a report attaches
    the current session's log, through the relay the reports already use.
  - The reporter id rule stays: left out unless the player turns it on.
  - No background uploads, no third-party analytics service.

## Co-op authority
Each peer logs what it sees; the host's log is the one that counts for world events
(dispatches, spawns, weather). Clients log their own inputs and frame times.

## Impact
- Affected specs: new `play-log` capability (ADDED: Session Play Log, Deck Checks From The Log,
  Play Logs With Reports).
- Affected code:
  - new `game/core/playlog/` (autoload, events list, file rotation);
  - one-line calls in the emergency, police, gang, weather, vehicle, garage, radio, map,
    pack and traffic code;
  - `game/core/report/` (attach the log, stage 2);
  - new `tools/playlog/` and `scripts/deck-playlog.sh`;
  - `<!-- playlog: ... -->` notes on the open Deck tasks;
  - docs (`CONTRIBUTING.md`, Deck checks).
