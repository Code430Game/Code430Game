## ADDED Requirements

### Requirement: Street-Side Parking
Roads with mapped street-side parking SHALL have a parking lane inside their paved width, kept out of the travel lanes, with parked cars in the bays by the hour.

#### Scenario: A street with bays
- **WHEN** the player drives a street whose parking lanes are mapped
- **THEN** parked cars stand in the parking lane and traffic drives past them in the travel lanes

### Requirement: Lot Layout Follows The Lot
Stall rows in a parking lot SHALL follow the lot's shape, with aisles reaching its entrances and leftover strips filled with single rows.

#### Scenario: An L-shaped lot
- **WHEN** a lot outline is L-shaped
- **THEN** each leg has rows along its own long axis and the aisles connect
