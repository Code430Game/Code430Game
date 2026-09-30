## ADDED Requirements

### Requirement: Pinned Engine Version
The project SHALL build with exactly one Godot version, recorded in `.godot-version`, and CI SHALL use that version.

#### Scenario: CI uses pinned version
- **WHEN** CI runs
- **THEN** it downloads and uses the Godot version in `.godot-version`

### Requirement: Graphics Presets
The game SHALL provide `deck` and `high` graphics presets, SHALL select `deck` automatically on Steam Deck hardware, and SHALL allow the player to override the selection.

#### Scenario: Launch on Steam Deck
- **WHEN** the game launches on a Steam Deck
- **THEN** the `deck` preset is active and SDFGI is disabled

#### Scenario: Manual override
- **WHEN** the player selects a different preset in settings
- **THEN** the selection persists across restarts

### Requirement: Controller-First Input
All game actions SHALL be usable with a gamepad alone.

#### Scenario: Boot with controller only
- **WHEN** the test scene is launched with only a gamepad connected
- **THEN** every defined action is reachable without keyboard or mouse

### Requirement: Linux Build Artifact
CI SHALL produce a runnable Linux export on every push to the main branch.

#### Scenario: Main branch push
- **WHEN** a commit is pushed to main
- **THEN** a Linux build artifact is available from the CI run

### Requirement: Pack Manifest Schema
Every pack SHALL contain a `pack.json` that validates against the published schema, and CI SHALL reject invalid manifests.

#### Scenario: Invalid manifest
- **WHEN** a pack under `packs/` has a manifest missing `type`
- **THEN** CI fails with a message naming the pack and the missing field
