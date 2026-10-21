## MODIFIED Requirements

### Requirement: One Of Everything
The proving ground SHALL contain at least one instance of every map feature the Ottawa pack exercises: signals and stop signs, a one-way pair, a bus lane with stops and a bus loop, sidewalks and crossings, an underpass, a road bridge and a footbridge, highway ramps with gores and shoulders, a dead end at the map edge, a surface lot with aisles, kerb parking, a multi-storey garage with an underground entrance, driveways and houses, shopfronts, a police station with a helipad, a hospital with an ambulance bay, a fire station, a park with trees and a tree row, water, and a rail stub with a station; and it SHALL be dressed as a town, with buildings on every block of every grid (houses, semis and terraces in the residential grid; shopfronts, apartment blocks and a few towers in the main city; offices and a warehouse row in the city) and tree rows along every avenue and the bank road, none of it placed on a road, a bank, the greenbelt, the park or the turf block.

#### Scenario: Feature checklist
- **WHEN** the feature checklist test runs against the committed pack
- **THEN** every listed feature is found in the pack's outputs

#### Scenario: Emergency services in one place
- **WHEN** a change needs a helipad, a hospital and a fire station within a short drive
- **THEN** the proving ground has all three within 600 m of the spawn

#### Scenario: Every block built on
- **WHEN** the dressing counts run against the committed pack
- **THEN** each grid meets its minimum building and tree-row counts and no footprint overlaps a road ribbon, a bank, the greenbelt, the park or the turf

#### Scenario: Deck budget
- **WHEN** the loop benchmark runs on the Deck with the dressed pack
- **THEN** render time stays within the budget and the per-chunk vegetation caps are respected
