## ADDED Requirements

### Requirement: Pack Discovery And Enabled Set
The game SHALL discover every pack folder in its search directories, validate each manifest against the schema for its `schema_version` (0 or 1), and load the packs listed as enabled in the user's settings in dependency order, with first-party packs enabled by default.

#### Scenario: New pack found
- **WHEN** a valid pack folder appears in `user://packs` that is not yet in the settings
- **THEN** it is enabled, loaded on the next start and announced once in the log and the Packs list

#### Scenario: Broken manifest
- **WHEN** a pack's `pack.json` has an unknown `schema_version`
- **THEN** the pack is skipped with a message naming the folder and the version, and the game starts

### Requirement: Data-Only Pack Safety
The loader SHALL refuse any data-only pack (map, character, story) that contains a file outside the allowed data, model, texture and audio types, and SHALL refuse a system pack that is not marked trusted.

#### Scenario: Script inside a story pack
- **WHEN** a story pack folder contains a `.gd` or `.tscn` file anywhere inside it
- **THEN** the pack is not loaded and the message names the pack and the offending file

### Requirement: Pack Namespaces
Every file in a pack SHALL be addressed as `pack_id:relative/path`, resolved only within that pack's folder, and no pack SHALL overwrite files of the base game or of another pack.

#### Scenario: Path escape
- **WHEN** content refers to `code430.example:../other/file.json`
- **THEN** resolution fails with an error naming the pack and the path, and nothing is read

#### Scenario: Shadowed pack
- **WHEN** the same pack id exists in `user://packs` and next to the executable
- **THEN** the `user://packs` copy is used and the other is logged as shadowed

### Requirement: Dependencies
A pack SHALL declare the packs it needs by id and semver range, and a pack whose dependency is missing or out of range SHALL be disabled with a message naming both packs and the range, without stopping the game.

#### Scenario: Story pack on another map
- **WHEN** a story pack depends on `code430.ottawa-centretown ^0.3` and the enabled map pack is `0.2.0`
- **THEN** the story pack is disabled and the Packs list shows the reason

### Requirement: Content Registry
The game SHALL expose every content item of a given type across the enabled packs, tagged with its pack id, filtered by the active tone mode's descriptor limits, and refreshed when the mode changes.

#### Scenario: Ads from two packs
- **WHEN** a map pack and an enabled story pack both carry `ads` content
- **THEN** billboards draw from both pools

#### Scenario: Mode narrows the pool
- **WHEN** the mode changes from `gritty` to `clean`
- **THEN** items whose descriptors exceed `clean` are no longer returned

### Requirement: Pack Set Summary
The game SHALL produce a deterministic summary of the enabled packs (id, version, content hash, sorted by id) for co-op verification, and a join SHALL be refused naming the first pack that differs or is missing on either side.

#### Scenario: Guest lacks a pack
- **WHEN** the host has a character pack enabled that the guest does not have
- **THEN** the guest is refused with a message naming that pack

### Requirement: Packs List
The pause menu SHALL list the discovered packs with name, version and type, let the player enable or disable non-map packs with a controller, let the player switch to another map pack (confirmed with a second press, restarting the game), warn on system packs and on two enabled map packs, and state that changes apply at the next load.

#### Scenario: Toggle with a controller
- **WHEN** the player moves to a character pack row and presses accept on the Deck
- **THEN** the pack's enabled state flips, is saved, and the footer says it applies at the next load

#### Scenario: Play another map
- **WHEN** the player presses accept twice on a map pack that is not the map in play, outside a co-op session
- **THEN** that map is saved as the player's map and the game restarts on it

### Requirement: First Character Pack
The base game SHALL ship a character pack carrying the creator's palettes and named starting presets as data, and the creator and pedestrians SHALL use those palettes when the pack is enabled and the built-in palettes otherwise.

#### Scenario: Pack disabled
- **WHEN** the character pack is disabled and the game restarts
- **THEN** the creator offers the built-in palettes and a previously saved character still renders
