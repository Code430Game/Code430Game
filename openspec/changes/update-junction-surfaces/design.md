# Design: junction surfaces

## The report
`JunctionReport` (`game/world/roads/junction_report.gd`) measures every junction on a pack.
It runs through `--junction-report` in the testbed, the headless
`world/build/junction_report.gd`, and tests. For each junction it lists:

- **bulge:** how far the outline reaches past what its arms need. That is each arm's ribbon out
  to its trim, the core between the arms' ends, and, between neighbouring arms, either the
  corner where their edges meet (a rounded corner fills it) or, under 90°, the strip between
  them.
- **gap:** how much of an arm's trimmed ribbon nothing covers, neither the outline nor another
  arm's own ribbon.
- **hull:** the outline crossed itself and fell back to a convex hull.
- **point-like:** an outline under 4 m² with three or more arms, or a node of three or more
  roads with no surface that is not a fork or merge.
- **terrain:** terrain over 5 cm above the surface. Junctions with a tunnel arm are counted
  apart: the terrain over a tunnel mouth is the hillside it goes into.

## Why T and Y junctions went wrong (#78, #79)
Between neighbouring arms whose edges did not meet in front of the node, the builder put the
corner `1.5` half widths along `normalize(da + db)`. For a road running straight on past a side
road, `da + db` is close to zero, so its direction was arbitrary:

- it pointed into the grass, giving a bulge (#78, both sides);
- or it pointed back across the road, giving a notch whose ribbons had been trimmed away, so
  grass showed through: the "C" (#79).

The same push sent the outline across itself at narrow Y splits. #78 also had a second cause:
the two one-way carriageways start exactly on the two-way road's centreline, a few degrees
apart. They shared one slot, so the surface pinched from 7 m to 3.5 m and bulged either side.

## What the builder does now
`JunctionBuilder` picks how the outline gets from one arm's cap to the next (`Corner`):

- **FILLET:** the rounded corner through where the edges cross. A crossing just behind one
  arm's end (a narrow road meeting a wide one at an obtuse angle) still counts: the walk runs
  along that arm's side back to its end, then rounds the corner.
- **ALONG:** for arms at least 150° apart whose edges do not meet in front of the node (a road
  running straight on), the outline follows each road's edge back to its end and steps across
  there when the width changes. Where stepping back would cross the outline (clustered
  junctions whose arms start metres from the centre), the walk is redone with STRAIGHT on
  those sides.
- **SHARP:** the outside of a bend, where the edges meet just behind the node; the outline turns
  there.
- **STRAIGHT:** cap to cap, closing the median between side-by-side carriageways.
- **PAIR:** for a narrow Y (arms under 30° apart whose ribbons still overlap a little way
  out), from the outermost cap corner on one side to the outermost on the other, skipping the
  inner corners that would cross. Both arms end at the same trim.

Near-parallel arms that overlap (under 12°) still share a slot, now widened to cover both
ribbons where they start. A divided road's two carriageways touching by under a metre used to
lose one of them from the outline. The outline drops repeated and collinear vertices, which
the triangulator rejects.

## Importer
- **Splits** (`forks.shape_splits`): a two-way road meeting two one-way carriageways that
  leave within 35° of each other, opposite it, one carrying traffic away and one toward the
  node. Each carriageway's end moves onto its own side of the two-way road, the one carrying
  traffic away on the right, and the move fades out over `blend_m`. 22 in Ottawa.
- **Corners** (`pack._junction_corners`): each corner of a junction on the ground gets a
  flattening line from the node toward where its edges meet, at the arms' heights there, so a
  junction in a cutting does not show the hillside in its corners.

## Curbs
The importer keeps a curb wherever a sidewalk runs beside the ribbon and no other road's
ribbon covers it. A curved road joining a junction does not cover it, so a curb stood inside
the junction. The game cuts curbs to the junction outlines when it loads the pack
(`BarrierBuilder.clip_curbs`), since only it has the outlines exactly. A curb along an outline
edge stays: that is a road running straight on, and the curb is on its edge.

## Ottawa, before and after (report, 2026-10-06)
| | before | after |
|---|---|---|
| junctions | 1,938 | 1,938 |
| bulging > 1.5 m | 464 (368 plain, 96 clustered) | 2 (clustered) |
| gaps > 0.5 m | 593 (538 plain, 55 clustered) | 44 (mostly clustered) |
| hull fallbacks | 73 | 21 |
| point-like / nodes with no surface | 0 / 0 | 0 / 0 |
| terrain above (outside tunnels) | 44 incl. tunnels | 14, none over 0.25 m (9 at tunnels apart) |
| curbs inside a junction | many (the pack test fails without the clip) | 0 |

The junctions the human reported:

| issue | junction | before | after |
|---|---|---|---|
| #78 | `n901218147` | bulge 1.8 m, gap 1.5 m | clean |
| #79 | `n6020506072` | gap 0.8 m | clean |

The worst before, for screenshots:
- `n905118988`, a 417 ramp merge at x -1214, z 106: grass blobs inside the motorway.
- `c4686481171`, a clustered crossing at x -987, z 64: median grass biting into the junction.
- `n901219352`, at x 971, z 978: a hull.

No point-like junction turned up. The ones the human had in mind may have been these blobs;
the report stays for new locations.

## Left
- **Big clustered junctions:** those with 5 to 10 arms make up most of the remaining gaps and
  hulls.
- **Cluster size:** no limit was added. Nothing in the report pointed at cluster growth for the
  T and Y cases, and a limit changes the road graph for every importer change still open.
- **Tunnel junctions:** listed apart rather than fixed.
