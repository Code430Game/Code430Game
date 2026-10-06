## ADDED Requirements

### Requirement: Readable Pursuit
While wanted, the HUD SHALL show whether police can see the player and, while hidden, how close the player is to losing them. The helicopter SHALL be escapable by speed or by cover, including dense tree canopy, and a patrol car whose officer has got out SHALL stay parked.

#### Scenario: Hidden under a deck
- **WHEN** a wanted player drives under a bridge deck and no unit sees them
- **THEN** the badge turns to the blinking hidden eye and its ring fills toward the time the current stars need, and the stars drop when it is full

#### Scenario: Spotted again
- **WHEN** a hidden player is seen by the helicopter
- **THEN** the badge turns solid with the helicopter mark and the ring empties

#### Scenario: Outrunning the helicopter
- **WHEN** a wanted player drives away in the open faster than the helicopter flies and stays beyond its sight range for its lost time
- **THEN** the helicopter loses them and goes to search where it last saw them

#### Scenario: Hiding under trees
- **WHEN** a wanted player stops under dense tree canopy in a park
- **THEN** the helicopter does not see them through the canopy

#### Scenario: An empty patrol car stays put
- **WHEN** an officer gets out of a patrol car and the player drives off
- **THEN** the empty patrol car does not move
