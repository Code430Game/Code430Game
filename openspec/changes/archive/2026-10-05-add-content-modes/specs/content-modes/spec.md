## ADDED Requirements

### Requirement: Mode Definitions
The game SHALL define tone modes as data, each with an id, a maximum level per content descriptor, mechanic flags, and a variant key, and SHALL ship `clean`, `gritty`, and `dystopia` with `gritty` as the default.

#### Scenario: Fresh install
- **WHEN** the game starts with no saved settings
- **THEN** the active mode is `gritty`

#### Scenario: Mode persists
- **WHEN** the player selects `clean` in settings and restarts the game
- **THEN** the active mode is `clean`

### Requirement: Content Descriptors
Every authored content item in pack data SHALL declare its content descriptors from the published closed list with a level per descriptor, and the pack validator SHALL reject unknown descriptors.

#### Scenario: Unknown descriptor
- **WHEN** a pack item declares a descriptor not in `content-descriptors.v0.json`
- **THEN** validation fails naming the item and the descriptor

### Requirement: Variant Selection
The game SHALL select, for each content item, the variant keyed to the active mode when present and allowed, otherwise the fallback when allowed, otherwise hide the item.

#### Scenario: Mode variant present
- **WHEN** the active mode is `dystopia` and an ad has a `dystopia` variant
- **THEN** the `dystopia` variant is shown

#### Scenario: Only fallback
- **WHEN** the active mode is `clean` and an ad has no `clean` variant but its fallback has no disallowed descriptors
- **THEN** the fallback is shown

#### Scenario: Nothing allowed
- **WHEN** the active mode is `clean` and neither the mode variant nor the fallback is allowed
- **THEN** the item is hidden and a warning is logged once per item

### Requirement: No Upward Leak
Content whose descriptors exceed the active mode's maximum levels SHALL never be shown, and the pack validator SHALL reject a variant whose descriptors exceed the mode it is keyed to.

#### Scenario: Strong content in clean variant
- **WHEN** a pack item's `clean` variant declares `gore: strong`
- **THEN** validation fails naming the item and the offending descriptor

### Requirement: Mechanic Flags
The active mode SHALL expose mechanic flags that gameplay systems can query, and systems SHALL query flags rather than mode ids.

#### Scenario: Violence flag
- **WHEN** the active mode is `clean`
- **THEN** `ContentMode.allows("violence")` returns false and `ContentMode.allows("violence", "stylized")` returns true

### Requirement: Pack Mode Support
Every pack manifest SHALL declare the modes it supports and its maximum descriptor levels, and the game SHALL warn when an enabled pack does not support the active mode.

#### Scenario: Unsupported mode
- **WHEN** the active mode is `clean` and an enabled story pack lists only `gritty` in `supported_modes`
- **THEN** the game shows a warning naming the pack before the session starts

### Requirement: Tone-Aware Billboards
Billboards SHALL display ads from the active packs' ad pool using variant selection, chosen deterministically per billboard id and session seed.

#### Scenario: Same seed, same ads
- **WHEN** the same map pack and session seed are loaded twice in the same mode
- **THEN** every billboard shows the same ad both times
