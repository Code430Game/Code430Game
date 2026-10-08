## MODIFIED Requirements

### Requirement: Content Descriptors
Every authored content item in pack data SHALL declare its content descriptors from the published closed list with a level per descriptor, the list SHALL include `minors` with the levels `none` and `present` (content without the key reads as `none`), and the pack validator SHALL reject unknown descriptors.

#### Scenario: Unknown descriptor
- **WHEN** a pack's content item declares a descriptor that is not in the closed list
- **THEN** the pack validator rejects the pack and names the descriptor

#### Scenario: Minors never leak upward
- **WHEN** a pack declares content with `minors: present` and the active mode's maximum for `minors` is `none`
- **THEN** that content is never shown or spawned in that mode
