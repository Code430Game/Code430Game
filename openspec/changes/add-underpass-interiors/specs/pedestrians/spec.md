## ADDED Requirements

### Requirement: Sheltering Population
When the active tone mode allows the `homelessness` descriptor, tunnels SHALL have shelter spots with belongings props along their walls, and the host SHALL spawn sheltering pedestrians at a configured share of the spots who sit or lie in place, are replicated with their pose, and leave the walking lane clear. When the mode does not allow it, tunnels SHALL have no spots, props or sheltering people.

#### Scenario: Gritty tunnel
- **WHEN** the player walks through the Chateau tunnel in the gritty mode
- **THEN** bedrolls and bags line the walls and some spots hold people sitting or lying who do not get up, and the player can walk past them down the middle

#### Scenario: Clean tunnel
- **WHEN** the mode is switched to clean and the chunk is rebuilt
- **THEN** the tunnel is lit and empty with no props

#### Scenario: Client view
- **WHEN** a client receives the pedestrian snapshot
- **THEN** sheltering people are drawn in the host's pose at the host's positions
