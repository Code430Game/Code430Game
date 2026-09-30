# street-dressing Specification

## Purpose
TBD - created by archiving change add-sidewalks-and-facades. Update Purpose after archive.
## Requirements
### Requirement: Sidewalks From Footways
The game SHALL build sidewalk ribbons for pedestrian ways in the map pack, with a curb step above the road surface, chunked like roads and exported with the GLB chunks, and the terrain SHALL be flattened under them at pack build.

#### Scenario: Downtown block
- **WHEN** the Ottawa pack is loaded on Bank Street downtown
- **THEN** concrete sidewalk ribbons run along both sides of the street between the road and the buildings

#### Scenario: Width
- **WHEN** a footway has `width=3`
- **THEN** its sidewalk ribbon is 3 m wide, otherwise the per-class default width applies

### Requirement: Procedural Facades
Building walls SHALL show windows per storey through a shader using metre-based UVs and the importer's storey height, with at least four treatments chosen by building type and height and varied per building.

#### Scenario: Office tower
- **WHEN** a building of type office taller than 20 m is rendered
- **THEN** its walls show a regular glass grid aligned to storeys

#### Scenario: House
- **WHEN** a building of type house is rendered
- **THEN** its walls show punched windows on a brick-like base, and two adjacent houses differ in tone

#### Scenario: Both presets
- **WHEN** the facade shader runs on the deck preset
- **THEN** it uses no textures and no screen-space effects

