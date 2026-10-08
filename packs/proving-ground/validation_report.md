# Road network validation: Double Cross

- Nodes: 123, edges: 196, total length: 35.97 km
- Connected components: 1 (largest has 123 nodes)
- Largest strongly connected component: 123 nodes
- Dead ends: bbox_edge 1, declared_noexit 0, likely_real 0, suspicious 0, parking 5
- Ramp problems: 0; one-way traps: 0 (plus 0 one-way stubs that simply dead-end, counted under dead ends)
- Defaulted fields: lanes 13, speed_kph 13, width 196

## Edge classes

| Class | Edges |
|---|---|
| motorway | 12 |
| motorway_link | 6 |
| parking | 6 |
| residential | 95 |
| secondary | 15 |
| service | 3 |
| tertiary | 59 |

## Connected components

The network is one connected component.

## Dead ends

### bbox_edge (1)

1 entries; listed in the JSON report only.

### declared_noexit (0)

none

### likely_real (0)

0 entries; listed in the JSON report only.

### suspicious (0)

none

### parking (5)

| Node | Way | Class | Name |
|---|---|---|---|
| 100930 | 1068 | parking | Police Drive |
| 100931 | 1069 | parking | Hospital Drive |
| 100932 | 1070 | parking | Fire Hall Drive |
| 100934 | 1072 | parking | - |
| 100935 | 1073 | parking | Garage Ramp |

## Ramp connectivity

Every *_link chain connects a major road at two or more points.

## One-way traps

No traps: every node inside the bbox can reach and be reached from the main network.

## Junction clusters

- 2 merged junctions; each road keeps its own line through them. Largest arm offsets from the centroid:
  - c100597 (OSM 100597, 100675): 4.988 m
  - c100407 (OSM 100407, 100445): 2.744 m

## Water

- Polygons written: 1; relations or ways skipped: 0

## Barriers

- median 4, guardrail 15, parapet 10, curb 8, roadblock 1

## Buildings

- Footprints written: 45; height from tag/levels/default: {'levels': 39, 'default': 6}

## Elevation

- Road height range: 56.595 m to 70.057 m
- Bridge/tunnel (fixed) vertices: 230; approach vertices raised or lowered to meet them: 54
- Conflicting bridge constraints: 0; bridge chains without a ground anchor: 0
- Vertices under a bridge footprint refilled from neighbours (DTM keeps decks): 23
- Worst residual grade: 0.08; edges still over their class limit: 0
- Shared heights: 225 deck and 6 ground vertices; largest step before 0.665 m, left after 0.269 m
- Span chains raised again for clearance after sharing: 0
- Decks short of their clearance over a road: 0
- Bridges inferred from untagged crossings: 0
