## ADDED Requirements

### Requirement: Factions As Tagged Data
Hostile factions SHALL be defined in data with content descriptors and per-mode variants, loaded from the base game and from packs, and the validator SHALL refuse a variant whose weapons the keyed mode does not allow.

#### Scenario: Clean variant
- **WHEN** the active mode is `clean` and a gang member is spawned
- **THEN** the member carries the faction's clean weapons (foam, paint, water) and never a lethal one

#### Scenario: Pack adds a faction
- **WHEN** a map pack ships `factions.v0.json` with a faction and a turf
- **THEN** that faction patrols that turf with no code change

### Requirement: Turf And Patrol
Each faction SHALL hold turf polygons placed by the map pack, SHALL keep members patrolling inside them on foot and in a faction car up to a cap, and SHALL show the turf on the map and the minimap.

#### Scenario: Members stay home
- **WHEN** the player stands outside every turf
- **THEN** no member leaves the turf to approach, and the map shows the turf's edge

### Requirement: Recognition And Threat
A member who sees the player inside the turf SHALL warn, then attack with the group, using melee and the mode's ranged variant, SHALL flee when outnumbered, hurt or when officers arrive, and SHALL regroup before patrolling again; reactions to the player's hits SHALL come from the mode data, with no knock-downs or blood in clean.

#### Scenario: Attacked on sight in gritty
- **WHEN** the player walks into the turf in `gritty` and a member sees them for the warning time
- **THEN** the group attacks, the nearest with a knife and others with the pistol at range, and the player's health falls on hits

#### Scenario: Tagged in clean
- **WHEN** the player walks into the turf in `clean`
- **THEN** the crew pelts them with paint and water, nobody is knocked down, and a tagged player is marked, not hurt

#### Scenario: Fighting back
- **WHEN** the player downs more than half of the group
- **THEN** the rest flee to the turf centre and downed members return after the respawn time

### Requirement: Gang Heat
The game SHALL keep a per-player gang heat that rises while members can see the player in turf, shows as a glyph on the HUD, sends the faction car at full, and drains after the player has been out of the turf for the configured time, separate from the wanted level.

#### Scenario: Leaving cools it
- **WHEN** the player leaves the turf and stays out for the configured time
- **THEN** the glyph empties and members on the next visit start from patrol
