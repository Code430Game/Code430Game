## ADDED Requirements

### Requirement: Officers And The Gang
Gunfire by a faction member SHALL be reported as that member's crime so officers respond to it, and officers SHALL fight members when the faction config says so, while the player stays wanted only for the player's own crimes.

#### Scenario: Officers join a gang fight
- **WHEN** a member fires at the player in `gritty` within an officer's sight
- **THEN** a patrol car comes to the member's position, officers engage the member, and the player's wanted level does not rise from the member's shot
