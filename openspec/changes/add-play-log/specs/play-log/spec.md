## ADDED Requirements

### Requirement: Session Play Log
The game SHALL write a play log for each session on the device: a first line describing the session (build, map packs, preset, tone, weather, time of day, co-op role), then one line per game event with its time, kind, place and fields, and a sample of the player's position and frame times each minute. Event kinds SHALL come from one list with their fields, and an unknown kind SHALL be refused. The log SHALL keep the last 30 sessions and SHALL hold no account, hardware id or free text. Writing it SHALL need no network.

#### Scenario: An ambulance call is logged
- **WHEN** a player knocks a pedestrian down and an ambulance arrives
- **THEN** that session's log has an `ambulance_dispatched` line and then an `ambulance_arrived` line with the place

#### Scenario: Old sessions are removed
- **WHEN** a 31st session starts
- **THEN** the oldest session's log is deleted and 30 remain

#### Scenario: A crash keeps the log
- **WHEN** the game is killed mid-session
- **THEN** the log up to the last flush, at most 10 seconds old, is readable line by line

### Requirement: Deck Checks From The Log
A tool SHALL copy the play logs from the Deck and check them against notes beside the open Deck tasks, each naming the event or events that confirm the task. It SHALL report each task as seen, with the session and time of the evidence, or not seen, and SHALL tick a seen task and note the evidence only when asked. A task asking how something feels SHALL remain the human's to answer.

#### Scenario: A session confirms a check
- **WHEN** the human plays a session in which rain starts, and `add-weather` 4.2 notes `weather_changed` with kind rain
- **THEN** the check reports that task as seen, naming the session and the minute rain started

#### Scenario: Something didn't happen
- **WHEN** no session has a `gang_spawned` event
- **THEN** the check reports `add-hostile-gang` 4.2 as not seen

### Requirement: Play Logs With Reports
The game SHALL attach the current session's play log to a bug report only when the player has turned on the setting to share play logs, which SHALL be off by default. The form SHALL say when the log goes with the report. The game SHALL NOT send play logs at any other time.

#### Scenario: Setting off
- **WHEN** a player with the setting off sends a report
- **THEN** the report carries no play log

#### Scenario: Setting on
- **WHEN** a player with the setting on sends a report
- **THEN** the issue has the session's play log attached and the form said so before sending
