## MODIFIED Requirements

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
