## ADDED Requirements

### Requirement: Homelessness Descriptor
The content descriptor list SHALL include `homelessness` with the shared levels, the `clean` mode SHALL allow none of it, the `gritty` and `dystopia` modes SHALL allow it at strong, and packs that omit the descriptor SHALL be read as declaring none.

#### Scenario: Mode limits
- **WHEN** `ContentMode.allows("homelessness")` is asked in each shipped mode
- **THEN** it is false in clean and true in gritty and dystopia

#### Scenario: Old pack
- **WHEN** a pack manifest written before the descriptor existed is validated
- **THEN** it passes and is treated as declaring no homelessness content
