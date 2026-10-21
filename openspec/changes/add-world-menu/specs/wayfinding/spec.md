## ADDED Requirements

### Requirement: Go To A Place
While Tester options is on, the map legend SHALL offer "Go to" on each place in a kind's list, including the pack's gang turfs as a kind of their own. "Go to" SHALL move the player there on foot, beside the place and facing the nearest street, leaving any car behind. It SHALL be refused while the player is wanted, with a line saying why.

#### Scenario: Go to the helipad
- **WHEN** a player with Tester options on opens the map, picks Helipad, then the helipad, and presses Y
- **THEN** the player stands on foot beside the helipad, facing the nearest street

#### Scenario: Not during a chase
- **WHEN** a player with two stars presses Y on a place
- **THEN** the player stays where they are and the legend says "Lose the police first"
