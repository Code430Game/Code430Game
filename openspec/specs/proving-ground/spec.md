# proving-ground Specification

## Purpose
Double Cross, a small fictional district generated from code into its own map pack, byte-identical on every run. It has one of every road and place feature the game handles, plus a figure-eight loop with a lap timer, so a change can be proved and benchmarked in minutes, away from the drift of live OpenStreetMap data.
## Requirements
### Requirement: Generated Test District
The repository SHALL contain a generator that produces a small fictional district as OpenStreetMap-shaped data, and the normal import pipeline with a synthetic elevation source SHALL turn it into the map pack `code430.proving-ground`, byte-identical on every run, with the generated pack committed and CI failing when a regeneration differs.

#### Scenario: Regeneration is identical
- **WHEN** CI runs the generator and the import on a clean checkout
- **THEN** the produced pack matches the committed `packs/proving-ground` file for file

#### Scenario: Importer change
- **WHEN** an importer stage changes its output and the regen script is run
- **THEN** the committed pack updates and the diff shows exactly what changed in the district

### Requirement: One Of Everything
The proving ground SHALL contain at least one instance of every map feature the Ottawa pack exercises: signals and stop signs, a one-way pair, a bus lane with stops and a bus loop, sidewalks and crossings, an underpass, a road bridge and a footbridge, highway ramps with gores and shoulders, a dead end at the map edge, a surface lot with aisles, kerb parking, a multi-storey garage with an underground entrance, driveways and houses, shopfronts, a police station with a helipad, a hospital with an ambulance bay, a fire station, a park with trees and a tree row, water, and a rail stub with a station.

#### Scenario: Feature checklist
- **WHEN** the feature checklist test runs against the committed pack
- **THEN** every listed feature is found in the pack's outputs

#### Scenario: Emergency services in one place
- **WHEN** a change needs a helipad, a hospital and a fire station within a short drive
- **THEN** the proving ground has all three within 600 m of the spawn

### Requirement: Drivable Loop With A Lap Timer
The proving ground's main route SHALL be a closed two-lane ring road with a start line, with the town grid inside it joined to the ring by side streets at signalled and stop-controlled junctions, and the game SHALL time laps across that line, showing the current and best lap on the HUD only while the player is on the loop.

#### Scenario: Into town off the ring
- **WHEN** the player turns off the ring at an avenue
- **THEN** they pass a signalled junction into the grid and can rejoin the ring on the far side

#### Scenario: A lap
- **WHEN** the player drives the loop and crosses the start line in its direction twice
- **THEN** the HUD shows the lap time and keeps the best of the session

#### Scenario: Off the loop
- **WHEN** the player leaves the loop for the town grid
- **THEN** the lap readout hides and a later crossing starts a fresh lap

### Requirement: Pack Selection
The testbed SHALL start on the pack named by `--pack=<id>`, else by the `map_pack` setting, else the Ottawa pack, and the Deck benchmark script SHALL take the same choice.

#### Scenario: Start on the proving ground
- **WHEN** the testbed starts with `--pack=code430.proving-ground`
- **THEN** the player spawns on the loop's start line in the proving ground

#### Scenario: Missing pack
- **WHEN** `--pack` names a pack that is not installed
- **THEN** the HUD says which pack was not found and where it looked

