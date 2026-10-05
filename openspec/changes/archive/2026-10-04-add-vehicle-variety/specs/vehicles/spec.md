## ADDED Requirements

### Requirement: Vehicle Catalogue
Vehicles SHALL be defined in a data catalogue with a body class, dimensions, mass, handling tunables, seats, a colour palette, descriptors and tone-mode livery variants, validated against a schema; packs MAY add entries that merge after the base set.

#### Scenario: Pack adds a vehicle
- **WHEN** an enabled pack ships a `vehicles.v0.json` with a new id
- **THEN** that vehicle can spawn in traffic and be driven, and the validator rejects a file with an unknown body class

### Requirement: Body Classes With LODs
The game SHALL generate each body class from one parametric generator with wheel wells, bumpers, pillars, inset glass, mirrors, lights and plates at LOD0 and a reduced LOD1, within the triangle budgets per class, with body vertices white so instance colour and a shared generated trim sheet paint them.

#### Scenario: Lineup
- **WHEN** every catalogue entry is built at LOD0 and LOD1
- **THEN** each mesh is within its triangle budget, every triangle faces outward, and the body surface is white while glass and lights are not

### Requirement: Player Car From The Catalogue
The player's car SHALL take its mesh, wheel layout, mass and handling tunables from a catalogue entry, and taking a traffic car SHALL keep that car's class and colour.

#### Scenario: Take a van
- **WHEN** the player takes a traffic van
- **THEN** the drivable car is a van with the van's mass and handling and the colour it had in traffic
