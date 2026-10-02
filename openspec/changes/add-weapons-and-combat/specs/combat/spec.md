## ADDED Requirements

### Requirement: Weapons As Tagged Data
Weapons SHALL be defined in data with a tone-neutral mechanic and per-mode variants, and the game SHALL equip the variant the active tone mode allows, refusing any variant marked lethal when the mode's `lethal_weapons` flag is off.

#### Scenario: Clean mode
- **WHEN** the active mode is `clean` and the player cycles to the sidearm slot
- **THEN** a paintball marker is in hand, firing paintballs, and no bullet weapon can be equipped

#### Scenario: Gritty mode
- **WHEN** the active mode is `gritty` and the player cycles to the sidearm slot
- **THEN** a pistol is in hand

#### Scenario: Mode switch
- **WHEN** the mode changes from `gritty` to `clean` during play
- **THEN** every slot swaps to its clean variant and all impact decals are cleared

### Requirement: Aiming And Firing
A player on foot SHALL aim over the shoulder with a reticle, fire hitscan guns, launch physics projectiles and swing melee weapons, with magazines and reloads, using one hit path for all three mechanics.

#### Scenario: Reload
- **WHEN** the magazine is empty and the player presses fire
- **THEN** the weapon reloads for its reload time and then fires

#### Scenario: Projectile hit
- **WHEN** a paintball strikes a wall
- **THEN** a paint splat decal appears at the contact point and the ball is gone

### Requirement: Player Health
Each player SHALL have health that lethal impacts and vehicle hits reduce, SHALL be down for a configured time at zero and respawn at the spawn point, and SHALL never be downed in a mode without lethal weapons.

#### Scenario: Downed
- **WHEN** a player's health reaches zero in `gritty`
- **THEN** the player is down for the configured time and then respawns at the spawn point with slots refilled

#### Scenario: Painted
- **WHEN** a player is hit by a paintball in `clean`
- **THEN** the character shows the paint and loses no health

### Requirement: Shots In Co-op
The shooter SHALL own its hit tests and report hits to the host, the host SHALL apply all damage to pedestrians, traffic and players, and peers in range SHALL see and hear the shot.

#### Scenario: Guest shoots a pedestrian
- **WHEN** a guest hits a host-simulated pedestrian
- **THEN** the host changes that pedestrian's state and every peer sees the same reaction in the next snapshot
