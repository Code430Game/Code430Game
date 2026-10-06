## ADDED Requirements

### Requirement: Weapon Wheel
The player SHALL be able to hold the next-weapon button to open a wheel of the weapon slots, built from the weapon data with an icon per slot, and choose one by direction, without the game pausing or slowing. A tap SHALL still step to the next slot, and a tile SHALL show the slot in hand while the wheel is closed.

#### Scenario: Choosing from the wheel
- **WHEN** the player on foot in gritty holds next weapon, points the right stick at the pistol and releases
- **THEN** the pistol is in hand, the wheel closes and the game ran at full speed throughout

#### Scenario: Cancelling the wheel
- **WHEN** the player opens the wheel and presses B
- **THEN** the wheel closes and the slot in hand is unchanged

#### Scenario: Tapping still cycles
- **WHEN** the player taps next weapon with fists in hand
- **THEN** the melee weapon is in hand and the idle tile flashes its icon without the wheel opening

#### Scenario: Segments follow the tone
- **WHEN** the tone changes from gritty to clean
- **THEN** the wheel's segments show the fists, paint brush and paintball gun icons in the clean accent colour

#### Scenario: A weapon from data gets a segment
- **WHEN** a weapon with no icon of its own is added to the weapon data
- **THEN** the wheel shows a segment for it using its model's icon, or the generic icon for its mechanic, and the game does not fail
