# street-dressing Specification

## Purpose
What sits along the roads between the kerbs and the buildings: sidewalks with slab joints, crossings, kerbs, building facades facing the street, and the props that make a block read as a street.

## Requirements

### Requirement: Sidewalks From Footways
The game SHALL build sidewalk ribbons for pedestrian ways in the map pack, with a curb step above the road surface, chunked like roads and exported with the GLB chunks, the terrain SHALL be flattened under them at pack build, and the ribbons SHALL show slab joints at a configured spacing with a concrete surface detail in both presets.

#### Scenario: Downtown block
- **WHEN** the Ottawa pack is loaded on Bank Street downtown
- **THEN** concrete sidewalk ribbons run along both sides of the street between the road and the buildings

#### Scenario: Width
- **WHEN** a footway has `width=3`
- **THEN** its sidewalk ribbon is 3 m wide, otherwise the per-class default width applies

#### Scenario: Slab joints
- **WHEN** the player walks 15 m along a downtown sidewalk
- **THEN** ten transverse joint lines pass underfoot at the configured slab length

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

### Requirement: Zebra Crossings
Pedestrian crossings in the map pack SHALL be drawn as white zebra stripes across the road, aligned with the crossing and clipped to the curbs, with a stop line on signalised approaches, in both presets.

#### Scenario: Crossing at a signalised junction
- **WHEN** the player approaches a crossing at a junction with traffic signals
- **THEN** the road shows zebra stripes across the crossing and a stop line before them

#### Scenario: Mid-block crossing
- **WHEN** a crossing way joins two sidewalks away from any junction
- **THEN** the road between the curbs shows zebra stripes along the crossing's direction
