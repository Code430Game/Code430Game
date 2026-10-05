# project-foundation Specification

## Purpose
The Godot project itself and the rules every feature lives within: the pinned engine version, the graphics presets for the Steam Deck and desktops, controller-first input with one layout per context that the player can rebind, the menus, local CI, and the original-content and licensing rules.

## Requirements

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
All game actions SHALL be usable with a gamepad alone. Actions SHALL belong to the on-foot context, the driving context or both, no gamepad button SHALL be bound to two actions in the same context, and the player SHALL be able to rebind any action's gamepad button or key in settings, with conflicting rebinds refused and a reset to defaults.

#### Scenario: Boot with controller only
- **WHEN** the test scene is launched with only a gamepad connected
- **THEN** the player can walk, drive, open the map and pause without touching a keyboard

#### Scenario: Handbrake does not reset the car
- **WHEN** the player pulls the handbrake while driving
- **THEN** the car slides and stays where it is; the reset only fires when its button is held for the hold time

#### Scenario: Conflicting rebind
- **WHEN** the player tries to bind the horn to the button already used by the handbrake
- **THEN** the binding is refused with a message naming the conflicting action

#### Scenario: Doc matches the map
- **WHEN** CI runs
- **THEN** `docs/controls.md` regenerated from the input map matches the committed file

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
