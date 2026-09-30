# Road network validation: Ottawa Centretown starter district

- Nodes: 1794, edges: 2361, total length: 193.405 km
- Connected components: 15 (largest has 1762 nodes)
- Largest strongly connected component: 1673 nodes
- Dead ends: bbox_edge 108, declared_noexit 0, likely_real 217, suspicious 1
- Ramp problems: 0; one-way traps: 0 (plus 26 one-way stubs that simply dead-end, counted under dead ends)
- Defaulted fields: lanes 269, speed_kph 590, width 2358

## Edge classes

| Class | Edges |
|---|---|
| living_street | 2 |
| motorway | 47 |
| motorway_link | 34 |
| primary | 271 |
| primary_link | 23 |
| residential | 839 |
| secondary | 601 |
| secondary_link | 14 |
| service | 306 |
| tertiary | 137 |
| tertiary_link | 3 |
| trunk | 3 |
| unclassified | 81 |

## Connected components

| Nodes | Edges | Likely cause | Classes | Sample names | Sample way ids |
|---|---|---|---|---|---|
| 1762 | 2341 | main network | living_street 2, motorway 47, motorway_link 34, primary 271, primary_link 23, residential 836, secondary 601, secondary_link 14, service 289, tertiary 137, tertiary_link 3, trunk 3, unclassified 81 | 1 Nelson Street, 2nd Avenue, 3rd Avenue, Academy Private, Albert Street, Alexandra Bridge, Allan Place, Allendale Private | 4651824, 4970097, 5023388, 9897059, 10227956, 10228426, 10228514, 10228741 |
| 4 | 3 | isolated island | residential 3 | Jemruss Private | 510049468, 510049469, 510049470 |
| 3 | 2 | connector filtered out (service=driveway) | service 2 | - | 128400701, 128400709 |
| 3 | 2 | connector filtered out (service=driveway) | service 2 | - | 128400702, 128400711 |
| 2 | 1 | connector filtered out (service=parking_aisle) | service 1 | - | 1240081713 |
| 2 | 1 | connector filtered out (service=drive-through, service=driveway) | service 1 | - | 1300895072 |
| 2 | 2 | connector filtered out (service=parking_aisle) | service 2 | - | 1494516283 |
| 2 | 2 | connector filtered out (service=parking_aisle) | service 2 | - | 1494516284, 1494516285 |
| 2 | 1 | connector filtered out (service=driveway) | service 1 | - | 1524335682 |
| 2 | 1 | connector filtered out (service=driveway) | service 1 | - | 128400695 |
| 2 | 1 | connector filtered out (service=parking_aisle) | service 1 | - | 128401786 |
| 2 | 1 | connector filtered out (service=parking_aisle) | service 1 | - | 128443794 |
| 2 | 1 | cut by bbox edge | service 1 | - | 374970532 |
| 2 | 1 | isolated island | service 1 | - | 549844121 |
| 2 | 1 | connector filtered out (service=parking_aisle) | service 1 | - | 789700974 |

## Dead ends

### bbox_edge (108)

108 entries; listed in the JSON report only.

### declared_noexit (0)

none

### likely_real (217)

217 entries; listed in the JSON report only.

### suspicious (1)

| Node | Way | Class | Name |
|---|---|---|---|
| 1236381993 | 732949596 | tertiary | Lyon Street North |

## Ramp connectivity

Every *_link chain connects a major road at two or more points.

## One-way traps

No traps: every node inside the bbox can reach and be reached from the main network.

## Water

- Polygons written: 18; relations or ways skipped: 0

## Buildings

- Footprints written: 10678; height from tag/levels/default: {'levels': 1691, 'default': 8966, 'tag': 18}

## Elevation

- Road height range: 43.319 m to 80.488 m
- Bridge/tunnel (fixed) vertices: 191; approach vertices raised or lowered to meet them: 225
- Conflicting bridge constraints: 4; bridge chains without a ground anchor: 0
- Vertices under a bridge footprint refilled from neighbours (DTM keeps decks): 170
- Worst residual grade: 0.1202; edges still over their class limit: 13
  w137483257.0, w399144346.0, w432336467.5, w76419763.0, w76420697.0, w76421113.0, w76423269.0, w76423834.0, w76424318.0, w76726964.0, w895111372.0, w895111373.0, w895111373.1
- Bridges inferred from untagged crossings: 0
