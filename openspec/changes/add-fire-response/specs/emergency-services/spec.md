## ADDED Requirements

### Requirement: Fire Response
A fire SHALL bring a fire truck from the nearest fire station, which SHALL put it out and return. Fires SHALL stay where they start and burn out on their own.

#### Scenario: A car catches fire after a crash
- **WHEN** a car takes a crash above the fire threshold and the tone allows flames
- **THEN** it burns, and a truck from the nearest fire station drives there and puts it out

#### Scenario: A fire left alone
- **WHEN** no truck reaches a fire
- **THEN** it burns down by itself and never spreads
