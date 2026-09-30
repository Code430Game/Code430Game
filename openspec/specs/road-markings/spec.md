# road-markings Specification

## Purpose
TBD - created by archiving change add-lane-markings. Update Purpose after archive.
## Requirements
### Requirement: Generated Lane Markings
The game SHALL generate lane markings from the road graph for every drivable edge: a centre line on two-way roads, dashed dividers between same-direction lanes, and edge lines, following each road's trimmed polyline.

#### Scenario: Two-way two-lane residential street
- **WHEN** a residential edge has one lane each way
- **THEN** it gets one yellow centre line and two white edge lines and no lane dividers

#### Scenario: One-way three-lane motorway
- **WHEN** a motorway edge has three forward lanes and none backward
- **THEN** it gets two white dashed dividers, two white edge lines, and no centre line

#### Scenario: Markings stop at junctions
- **WHEN** a road ends at a junction with a trim distance
- **THEN** its markings end at the same trimmed point as its ribbon

### Requirement: Marking Rules As Data
Line widths, dash lengths, gaps, colours, and per-class centre line style SHALL come from a rules file, not code constants.

#### Scenario: Change dash length
- **WHEN** the dash length in the rules file is changed
- **THEN** regenerated markings use the new length without a code change

### Requirement: Markings In Chunks
Markings SHALL be built per chunk, exported with the GLB chunks, and face upward.

#### Scenario: GLB round trip
- **WHEN** a chunk with markings is exported and imported
- **THEN** the imported chunk has a `markings_lod0` mesh with the same vertex count

