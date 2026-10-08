## ADDED Requirements

### Requirement: Layer Inputs From Files
Every importer layer that is fetched from Overpass SHALL also accept its payload from a local JSON file, so a generated or cached dataset builds a complete pack with no network access.

#### Scenario: Offline pack build
- **WHEN** the importer runs with `--osm-json` and a `--*-json` file for every enabled layer
- **THEN** it writes a complete pack without any Overpass request and the road graph's meta records each layer's file as its source
