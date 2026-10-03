## ADDED Requirements

### Requirement: In-Game Issue Report Form
The game SHALL let a player report a problem from inside the game: from the pause menu on any input device, by holding the pause button for a second, and with F8 on the keyboard. The form SHALL capture the frame that was on screen when it was opened as the screenshot, with a preview and a toggle to leave it out. It SHALL sort the report by an area drop-down and a severity drop-down and offer one optional text area for what happened. The title SHALL always be generated from the area, the severity and the place. The player MAY include this install's reporter id, a random id made once per install and never derived from the hardware; it is left out unless the player turns it on. Every control SHALL work with a controller. The text area SHALL use the Steam Deck's on-screen keyboard and SHALL be left with Enter, Escape or any controller button. While the player types, keys SHALL reach only the text area.

#### Scenario: Report from the pause menu on the Deck
- **WHEN** a player driving on the Deck opens the pause menu and chooses "Report a problem"
- **THEN** the form opens with a thumbnail of the frame from just before the menu appeared, the area and severity drop-downs, the text area and the reporter id choice, all reachable with the controller

#### Scenario: Hold Menu to report
- **WHEN** a player holds Menu for a second while driving
- **THEN** the game pauses at once and the report form opens with the frame from before the pause as its screenshot, while a tap of Menu only pauses

#### Scenario: Generated title
- **WHEN** a player sends a report about Roads and junctions, severity Annoying, at x 237, z 18 on Elgin Street
- **THEN** the report's title is "Report: Roads and junctions · Annoying · Elgin Street (x 237, z 18)"

#### Scenario: Typing on the Deck
- **WHEN** a player types in the text area with the Deck's keyboard, including the letter m, and presses its Enter key
- **THEN** the m is typed and the map does not open, and typing ends with the form still open

#### Scenario: Screenshot left out
- **WHEN** the player turns the screenshot toggle off before sending
- **THEN** no image is saved or sent with that report

### Requirement: Report Diagnostics
Each report SHALL carry diagnostics without the player typing them:
- the build (commit, branch, build date, dirty flag) and the Godot version;
- the OS, CPU, GPU and driver, memory, resolution, and whether a Steam Deck was detected;
- the graphics preset, tone mode, loaded packs, and co-op role and peer count;
- the player's position, heading, whether they are on foot or in a car, the nearest road name, edge id and junction id, and the time of day;
- frame time over the last 30 seconds;
- the last 200 lines of the game log.

The home directory and the OS account name SHALL be redacted from the diagnostics and the log tail. Generic account names such as the Steam Deck's `deck` identify nobody, so they are kept; the home directory is still redacted. What the player types is sent as typed. Before anything is sent, the form SHALL show every field that will be sent.

#### Scenario: Exported build identifies itself
- **WHEN** a report is made from a build packaged by `scripts/package-linux.sh`
- **THEN** its diagnostics name the commit and build date the package was made from

#### Scenario: Paths are redacted
- **WHEN** the log tail contains a path under the player's home directory
- **THEN** the saved and sent report shows that path starting with `~`, and neither the home directory nor a personal account name appears in its diagnostics or log tail

### Requirement: Reports Filed Without an Account
The game SHALL file reports as GitHub issues without the player having or signing in to any account. It SHALL send them to a relay service that holds the repository credentials. The game SHALL contain no credential: only the relay's URL. The relay SHALL:
- create the issue with the area, severity, `in-game-report` and `needs-triage` labels, the diagnostics, and the screenshot linked from the issue;
- file a given report id at most once, however often it is retried;
- enforce per-sender rate limits, size limits and schema validation, and defuse mentions and markup;
- keep no copy of reports or IP addresses;
- have a switch that stops it from accepting reports without a game update.

#### Scenario: Player without a GitHub account files a report
- **WHEN** a player with no GitHub account sends a report with a screenshot while online
- **THEN** an issue appears in the configured repository with the report's title, labels, description, screenshot and diagnostics, and the form shows the issue's link

#### Scenario: Retry after a lost response
- **WHEN** the relay files a report but the game never receives the answer and sends the same report again
- **THEN** no second issue is created, and the game receives the first issue's link

#### Scenario: Flooding is refused
- **WHEN** one sender submits a sixth report within an hour
- **THEN** the relay refuses it with a retry time, and the game keeps the report queued until then

### Requirement: Reports Are Never Lost
The game SHALL save every report locally before trying to send it. A report that cannot be sent SHALL stay queued and be retried later, and the player SHALL be able to see, send or delete queued reports. This applies when the device is offline, the relay is not configured or is switched off, or the relay refuses the report for now. On desktop, the player SHALL be able to file a queued report through GitHub's new-issue page in the browser instead.

#### Scenario: Report made offline on the Deck
- **WHEN** a player sends a report while the Deck has no network, then plays on after the network returns
- **THEN** the report is saved on the Deck at once, is listed as queued in the form, and is filed automatically once the relay can be reached

#### Scenario: No relay configured
- **WHEN** the build's report configuration has no relay URL
- **THEN** reports are saved locally, and on desktop the form offers to open GitHub's new-issue page prefilled with the title, labels and body and reveals the screenshot's folder
