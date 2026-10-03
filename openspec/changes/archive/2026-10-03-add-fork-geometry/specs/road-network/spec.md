## ADDED Requirements

### Requirement: Forks And Merges
Where a narrower road leaves or joins a through road at a shallow angle, the importer SHALL move the link's end to the through road's outer edge, fading the move out along the link, and SHALL tag the node as a fork or merge. The game SHALL draw no junction polygon there, SHALL taper the through road's width across the node, and SHALL NOT treat the node as a junction for traffic priority.

#### Scenario: Off-ramp
- **WHEN** a motorway link leaves a motorway at a node where the motorway continues straight
- **THEN** the link's ribbon starts on the motorway's outer lane and peels away from its edge, no junction polygon covers the motorway, and traffic on the motorway does not yield at the node

#### Scenario: Side street
- **WHEN** a road meets a through road at a steep angle
- **THEN** the node stays an ordinary junction with a polygon and trims
