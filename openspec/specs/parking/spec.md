# parking Specification

## Purpose
Parking lots from OSM as drivable surfaces with marked stalls, filled with parked cars that follow the lot type and the hour, the same for every peer, which the player can hit and take.

## Requirements

### Requirement: Parking Lots In Map Packs
The import tool SHALL write `parking.v0.json` with every `amenity=parking` feature intersecting the bbox: clipped rings, kind, capacity, access, fee, operator, stall direction derived from the lot's aisles, entrances where aisles or driveways meet streets, and street-side parking bays from `parking:*` tags on street edges.

#### Scenario: Surface lot with an aisle
- **WHEN** a parking polygon contains a `service=parking_aisle` way that meets a street
- **THEN** the exported lot has kind `surface`, a stall direction along that aisle, and an entrance at the street node

#### Scenario: Street-side bays
- **WHEN** a residential way is tagged `parking:right=lane`
- **THEN** the exported edge carries a bay on its right side along its length

### Requirement: Built Lots With Stalls
The game SHALL build surface lots as an asphalt slab with kerb, stall markings laid from the stall direction at the configured size and orientation, curb stops, and an entrance sign, chunked with collision, in both presets, and SHALL draw lots on the overview map and minimap.

#### Scenario: Lot in the Market
- **WHEN** the player drives into a surface lot off a Market street
- **THEN** the lot is paved, marked with stalls, and the car can stop in a stall

#### Scenario: Diagonal lot
- **WHEN** a lot is tagged `orientation=diagonal`
- **THEN** its stalls are angled along the aisle direction

### Requirement: Parked Cars
Stalls SHALL be filled with parked cars from the vehicle catalogue at a seeded occupancy that varies by lot type and hour, identical on every peer, drawn per chunk with LODs under a per-preset cap, with physics bodies only for the few nearest a player, and the player SHALL be able to take a parked car under the same rule as a traffic car.

#### Scenario: Deterministic fill
- **WHEN** two peers load the same pack at the same hour
- **THEN** every lot shows the same cars in the same stalls

#### Scenario: Take a parked car
- **WHEN** the player presses interact next to a parked car
- **THEN** the player drives away in it and the stall stays empty for the session

#### Scenario: Deck cap
- **WHEN** a chunk holds more parked cars than the preset cap
- **THEN** the farthest stalls from any player stay empty and frame time stays within budget

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
