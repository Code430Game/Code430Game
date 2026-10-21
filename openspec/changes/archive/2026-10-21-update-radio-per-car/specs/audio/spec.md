## ADDED Requirements

### Requirement: Station Per Car
Each drivable car SHALL keep its own radio station: the player's car keeps the station they chose, and a taken car plays the station its owner left on.

#### Scenario: Swapping cars
- **WHEN** the player leaves their car on Redline FM, takes a traffic car, then returns to their car
- **THEN** the taken car plays its own station and the player's car is on Redline FM again
