# Road network validation: Test district west

- Nodes: 22, edges: 20, total length: 1.71 km
- Connected components: 2 (largest has 16 nodes)
- Largest strongly connected component: 14 nodes
- Dead ends: bbox_edge 11, declared_noexit 0, likely_real 0, suspicious 0, parking 1
- Ramp problems: 0; one-way traps: 0 (plus 0 one-way stubs that simply dead-end, counted under dead ends)
- Defaulted fields: lanes 1, speed_kph 1, width 20

## Edge classes

| Class | Edges |
|---|---|
| motorway | 5 |
| motorway_link | 1 |
| parking | 1 |
| residential | 6 |
| secondary | 3 |
| tertiary | 4 |

## Connected components

| Nodes | Edges | Likely cause | Classes | Sample names | Sample way ids |
|---|---|---|---|---|---|
| 16 | 15 | main network | motorway 2, parking 1, residential 6, secondary 2, tertiary 4 | Depot Avenue, Double Cross Highway, Double Cross Loop, Fire Hall Drive, Fourth Street, Quay Avenue, Riverside Avenue, Station Avenue | 1001, 1007, 1008, 1013, 1026, 1027, 1032, 1077 |
| 6 | 5 | cut by bbox edge | motorway 3, motorway_link 1, secondary 1 | City Entrance, Double Cross Highway, Double Cross Loop | 1000, 1005, 1006, 1070 |

## Dead ends

### bbox_edge (11)

11 entries; listed in the JSON report only.

### declared_noexit (0)

none

### likely_real (0)

0 entries; listed in the JSON report only.

### suspicious (0)

none

### parking (1)

| Node | Way | Class | Name |
|---|---|---|---|
| 101217 | 1077 | parking | Fire Hall Drive |

## Ramp connectivity

Every *_link chain connects a major road at two or more points.

## One-way traps

No traps: every node inside the bbox can reach and be reached from the main network.

## Junction clusters

- 31 merged junctions; each road keeps its own line through them. Largest arm offsets from the centroid:
  - c100666 (OSM 100666, 100863): 4.988 m
  - c100412 (OSM 100412, 100460): 2.744 m
  - c100826 (OSM 100826, 100827): 2.394 m
  - c100899 (OSM 100899, 100900): 2.238 m
  - c100587 (OSM 100587, 100588): 2.155 m
  - c100589 (OSM 100589, 100590): 1.672 m
  - c100719 (OSM 100719, 100720): 1.6 m
  - c100582 (OSM 100582, 100583): 0.0 m
  - c100679 (OSM 100679, 100680): 0.0 m
  - c100704 (OSM 100704, 100705): 0.0 m

## Water

- Polygons written: 0; relations or ways skipped: 0

## Barriers

- median 2, parapet 2, guardrail 2, roadblock 11

## Buildings

- Footprints written: 45; height from tag/levels/default: {'levels': 2490, 'default': 6, 'tag': 15}

## Elevation

- Road height range: 56.555 m to 70.083 m
- Bridge/tunnel (fixed) vertices: 230; approach vertices raised or lowered to meet them: 54
- Conflicting bridge constraints: 0; bridge chains without a ground anchor: 0
- Vertices under a bridge footprint refilled from neighbours (DTM keeps decks): 34
- Worst residual grade: 0.08; edges still over their class limit: 0
- Shared heights: 225 deck and 6 ground vertices; largest step before 0.665 m, left after 0.269 m
- Span chains raised again for clearance after sharing: 0
- Decks short of their clearance over a road: 0
- Bridges inferred from untagged crossings: 0
