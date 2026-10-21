## ADDED Requirements

### Requirement: Map Legend And Places
The full map SHALL show a legend of the kinds of places in the pack, each as its icon and name, and SHALL let the player open a kind to list its places with real street addresses (or the nearest street when the data has none), then pick one to centre the map on it, going back a level with B.

#### Scenario: Finding a police station
- **WHEN** the player opens the map, selects Police in the legend and picks the first place
- **THEN** the map centres on that police station and highlights it, and the list showed its name and street address

#### Scenario: A place with no address tags
- **WHEN** a service place in the OSM data has no address tags
- **THEN** its list entry reads "on" followed by the nearest street's name
