## ADDED Requirements

### Requirement: Flyable Helicopter
The police helicopter SHALL park on its helipad when idle, and the player SHALL be able to take it there and fly it with arcade controls that hold position when released. The player SHALL be able to get out only when landed or hovering low. Stealing it SHALL be a crime, and crashes SHALL follow the tone's outcome data.

#### Scenario: Stealing it from the pad
- **WHEN** the player walks up to the parked police helicopter and presses get in
- **THEN** the player is flying it, the wanted level rises by two stars, and the police have no air unit while the player has it

#### Scenario: Letting go of the controls
- **WHEN** the player releases every flight control at speed
- **THEN** the helicopter slows, levels and holds its height

#### Scenario: Getting out in the air
- **WHEN** the player presses get out 30 m above the ground
- **THEN** nothing happens except a "Land first" hint

#### Scenario: Hitting a building in clean
- **WHEN** the player flies into a building in the clean tone
- **THEN** the helicopter bounces off and lands gently, and is not destroyed
