## MODIFIED Requirements

### Requirement: Character Profile
The player character's look SHALL be described by a profile (skin, hair style and colour, beard, glasses, top, jacket, trousers, shoes, hat, height, build) that is random on first start so nothing blocks play. The body built from it SHALL have a face, jointed limbs and a walk cycle driven by movement, and SHALL be worn by the on-foot player, by that player's replica on other peers, and in pre-posed variants by pedestrians.

#### Scenario: First start
- **WHEN** the game starts with no saved characters
- **THEN** the player spawns wearing a random profile, and that profile is saved as the last created character

#### Scenario: Walking
- **WHEN** the player moves on foot
- **THEN** the body's legs and arms swing in step with the distance covered and rest when the player stops

#### Scenario: Co-op
- **WHEN** a guest with a saved character joins a host
- **THEN** the host sees the guest's body built from the guest's profile, walking when the guest walks
