## ADDED Requirements

### Requirement: Underground Garages
The pack SHALL describe underground garages built from OSM parking entrances and underground parking (one level each, with a footprint from a lot outline, a served building or the capacity, and a ramp from each entrance). The game SHALL let a car drive down each ramp into the garage, park in its stalls, and take its parked cars.

#### Scenario: Drive into the NAC garage
- **WHEN** the player drives into a "NAC underground parking" entrance
- **THEN** a ramp leads down to a lit garage level with columns, stalls and parked cars
- **AND** there is no step or terrain wall on the way

#### Scenario: Private garage entrance
- **WHEN** the player drives to the entrance of a private or unnamed garage
- **THEN** the driveway ramps down to a closed garage door in a concrete portal, not a terrain wall

#### Scenario: Entrance without an outline
- **WHEN** an entrance has no garage outline and no building beside it
- **THEN** a garage sized from its capacity (or the default) is placed behind the entrance
