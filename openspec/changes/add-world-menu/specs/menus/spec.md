## ADDED Requirements

### Requirement: World Tab
The pause menu SHALL have a World tab with Weather (Auto or one weather state), Time (Auto or a fixed hour) and Day length. A picked weather state SHALL blend in over its usual transition and hold until the player picks another or Auto; Auto SHALL let the weather table walk again from the current state. A fixed hour SHALL set the clock and stop it; Auto SHALL run it from there. In co-op the host's choices SHALL apply to everyone, and a guest SHALL see them without being able to change them.

#### Scenario: Rain on demand
- **WHEN** a player on the Deck picks Rain on the World tab and resumes
- **THEN** rain blends in over its transition and keeps falling past its usual duration until the player picks Auto or another state

#### Scenario: Night now
- **WHEN** a player picks 22:00
- **THEN** the clock shows 22:00 and stays there, and night lighting and headlights are on

#### Scenario: A guest sees the host's weather
- **WHEN** the host picks Snow and a guest opens the World tab
- **THEN** the guest's tab shows Snow, greyed out, and snow falls for both
