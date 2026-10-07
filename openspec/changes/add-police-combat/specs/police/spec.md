## ADDED Requirements

### Requirement: Fighting The Police
The player's weapons and fists SHALL reach officers. Officers SHALL react by tone from mode data, never by mode id: they are knocked down in gritty and dystopia, and tagged out without a knock-down in clean. Hitting or downing an officer SHALL raise the wanted level and bring backup.

#### Scenario: Shooting an officer in gritty
- **WHEN** the player shoots an officer with the pistol until their toughness is spent
- **THEN** the officer is knocked down, the wanted level rises by a star for the assault and another for the officer down, and a patrol car heads for that spot

#### Scenario: Painting an officer in clean
- **WHEN** the player hits an officer with the paintball gun until their toughness is spent
- **THEN** the officer sits with their hands up for a while and walks back to their car, and is never knocked down

#### Scenario: A downed officer stops watching
- **WHEN** the only officer who could see the player is knocked down
- **THEN** that officer no longer counts as seeing the player
