## ADDED Requirements

### Requirement: Character Profile
The player character's look SHALL be described by a profile (skin, hair, clothing colours, hat, height, build) that is random on first start so nothing blocks play, and the body built from it SHALL be worn by the on-foot player and by that player's replica on other peers.

#### Scenario: First start
- **WHEN** the game starts with no saved characters
- **THEN** the player spawns wearing a random profile, and that profile is saved as the last created character

#### Scenario: Co-op
- **WHEN** a guest with a saved character joins a host
- **THEN** the host sees the guest's body built from the guest's profile

### Requirement: Character Creator
The pause menu SHALL open a creator where the player adjusts each profile field with a controller, sees the result immediately, randomises, saves the body as a preset, loads or deletes a preset, and leaves with the body applied and stored as the last created character.

#### Scenario: Tweak and keep
- **WHEN** the player changes the top colour and presses Done
- **THEN** the on-foot body shows the new colour, and the next start loads the same body

#### Scenario: Presets
- **WHEN** the player saves a preset, randomises, then loads that preset
- **THEN** the body matches the saved preset
