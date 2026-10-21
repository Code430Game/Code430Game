## 1. The log
- [ ] 1.1 `PlayLog` autoload: session header, `event(kind, fields)`, the minute sample (position, frame times), JSON Lines under `user://playlog/`, last 30 kept, flushed on quit and every 10 s; `events.json` with each kind's fields; tests (header, an unknown kind refused, rotation, a crash leaves a readable file)
- [ ] 1.2 Events in the game: ambulance dispatched and arrived, busted, wasted, wanted level, police helicopter spawned, sight lost and chase lost, gang spawned and fight started, weather changed, vehicle entered, garage entered, radio station, legend place picked, pack toggled, the night headlight count; co-op: world events from the host only; tests per event on the existing scenes

## 2. Checks
- [ ] 2.1 `tools/playlog`: read logs, `check` against `<!-- playlog: ... -->` notes in the active changes' `tasks.md` (an event kind, or kind with field conditions, or all of a list), print seen or not seen with the evidence, `--tick` to tick and note; tests on fixture logs and a fixture tasks file
- [ ] 2.2 `scripts/deck-playlog.sh [host]`: copy the Deck's logs into `build/playlog/`, then run the check
- [ ] 2.3 Playlog notes on today's open Deck tasks; split each feel question from its factual half; `CONTRIBUTING.md` and `docs/open-work.md` say how a Deck check is confirmed now
- [ ] 2.4 Deck: package, deploy, benchmark against main (unchanged within noise)
- [ ] 2.5 **Stop: the human plays a session on the Deck without notes, and the check reports what happened**

## 3. Testers (stage 2)
- [ ] 3.1 Setting "Share play logs with bug reports" (off by default); the report form says when the log goes with it; the relay accepts and attaches it (size cap); reporter id rule unchanged; tests on the payload with the setting off and on
- [ ] 3.2 **Stop: the human sends a report with the log attached and reads it on the issue**
