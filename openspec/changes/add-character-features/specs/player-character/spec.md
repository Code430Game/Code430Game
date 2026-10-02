## MODIFIED Requirements

### Requirement: Character Profile
The player character's look SHALL be described by a profile (skin, hair style and colour, beard, eyewear, eye colour, brow and mouth shape, top and pattern, jacket or coat or hoodie, trousers or shorts or skirt, shoes, hat, accessories, height, build, belly, shoulders) that is random on first start so nothing blocks play, and older saved profiles SHALL load with defaults for fields they lack. The body built from it SHALL have a face, jointed limbs, garment geometry and a walk cycle driven by movement, SHALL be produced at three levels of detail switched by distance, and SHALL be worn by the on-foot player, by that player's replica on other peers, and by pedestrians.

#### Scenario: First start
- **WHEN** the game starts with no saved characters
- **THEN** the player spawns wearing a random profile, and that profile is saved as the last created character

#### Scenario: Old preset
- **WHEN** a preset saved before the new fields existed is loaded
- **THEN** the body looks as it did when the preset was saved

#### Scenario: Walking
- **WHEN** the player moves on foot
- **THEN** the body's legs and arms swing in step with the distance covered and rest when the player stops

#### Scenario: Remote player far away
- **WHEN** another peer's character is 200 m away
- **THEN** its lowest-detail body is drawn, and the full body returns as it approaches within 60 m

#### Scenario: Co-op
- **WHEN** a guest with a saved character joins a host
- **THEN** the host sees the guest's body built from the guest's profile, walking when the guest walks
