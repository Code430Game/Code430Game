## MODIFIED Requirements

### Requirement: OSM Road Import
The import tool SHALL produce a road graph from OpenStreetMap data for a given bounding box, preserving connectivity, one-way direction, road class, lanes, bridges, tunnels, and layers, and SHALL keep `service=parking_aisle` and `service=driveway` ways as edges of class `parking` connected to the streets they meet.

#### Scenario: Import a bounding box
- **WHEN** the tool runs with a bounding box
- **THEN** it writes `road_graph.v0.json` that validates against the published schema
- **AND** every edge references the OSM way it came from

#### Scenario: One-way preserved
- **WHEN** an OSM way is tagged `oneway=yes`
- **THEN** the corresponding edge is one-way in the same direction

#### Scenario: Parking aisle kept
- **WHEN** a `highway=service` way is tagged `service=parking_aisle`
- **THEN** it is exported as an edge of class `parking` sharing nodes with the street it joins, and the validation report counts it under that class, not among real-street dead ends
