# police Specification

## Purpose
Police patrol the city, raise a wanted level when the player commits crimes, and chase, block and arrest the player, with the police helicopter joining at higher levels.

## Requirements

### Requirement: Wanted Level
Witnessed crimes SHALL raise a wanted level of 0 to 3 stars shown on the HUD, and the level SHALL drop a star each time no officer has seen the player for the losing time, ending the chase at zero.

#### Scenario: Shooting near a bystander
- **WHEN** the player fires a gun in `gritty` within the witness distance of a walker
- **THEN** the wanted level rises to at least one star

#### Scenario: Losing the police
- **WHEN** no officer sees the player for the losing time at one star
- **THEN** the wanted level drops to zero and the police cars leave

### Requirement: Pursuit
With a wanted level the game SHALL spawn police cars out of view that chase the player, and officers SHALL get out to chase a player on foot.

#### Scenario: Chase
- **WHEN** the player has two stars
- **THEN** police cars with flashing light bars and sirens drive toward the player

### Requirement: Busted And Wasted
A player held still beside an officer SHALL be busted, and in modes with lethal weapons a player whose health reaches zero SHALL be wasted; both clear the wanted level and respawn the player. In `clean` officers carry a net gun that only holds the player in place.

#### Scenario: Net gun in clean
- **WHEN** an officer's net hits the player in `clean`
- **THEN** the player cannot move or shoot for the net time and loses no health

### Requirement: Helicopter At Three Stars
At three stars a police helicopter SHALL take off from the nearest helipad, circle the player and count as police sight unless the player is under cover, with a searchlight at night, and SHALL return when the level drops.

#### Scenario: Hiding under a bridge
- **WHEN** the helicopter is circling and the player drives under a bridge deck
- **THEN** the helicopter loses sight and the losing timer runs
